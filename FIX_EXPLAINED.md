# Zero Throughput - Root Cause and Fix

## The Problem

**Symptom**: Live throughput shows 0.00 Mbps even though workers connect successfully.

**Root Cause**: The TCP MAX LOAD code was using `socket.addStream()` which blocks execution:

```dart
// OLD CODE (BLOCKING):
Stream<List<int>> generator() async* {
  while (isRunning()) {
    onBytesSent(buffer.length);  // ❌ This never actually runs!
    yield buffer;
  }
}
await socket.addStream(generator());  // Blocks here forever
```

The problem:
1. `addStream()` pumps data from the generator stream
2. Generator yields buffers but never actually executes `onBytesSent()`
3. The periodic timer (500ms) that reports bytes NEVER gets a chance to run
4. `bytesAccumulator` stays at 0
5. No metrics sent to main isolate
6. UI shows 0 throughput

## The Fix

**NEW CODE (Non-blocking)**:
```dart
// Direct writes with periodic yielding
int writeCount = 0;
while (isRunning()) {
  socket.add(buffer);
  onBytesSent(buffer.length);  // ✅ This executes!
  writeCount++;
  // Yield every 10 writes to let timer run
  if (writeCount % 10 == 0) {
    await Future.delayed(Duration.zero);
  }
}
```

This:
1. Writes buffers directly to socket
2. Immediately calls `onBytesSent()` to increment counter
3. Yields control every 10 writes so the periodic timer can run
4. Timer sees accumulated bytes and sends reports
5. Main isolate receives metrics
6. UI displays throughput

## Testing

Rebuild and run:
```bash
flutter run
```

You should now see in console:
```
WORKER 0 timer tick: accumulated=10240 bytes
WORKER 0 sent report: 10240 bytes
DEBUG: Received report: 10240 bytes
DEBUG TIMER: Emitting sample with 327680.0 bps
```

And the chart should show non-zero Mbps values!

## Debug Logging Added

Temporary debug prints to verify data flow:
- Worker side: Shows bytes accumulated and reports sent
- Main side: Shows reports received and samples emitted

**Remove these later** once confirmed working (search for "DEBUG" in traffic_engine.dart).

## Why Router on Port 80 Works Now

Routers typically accept TCP on port 80 (HTTP) but don't respond with data.
The old `addStream()` was waiting for backpressure signals, the new direct
writes just pump data continuously regardless of server response.

For maximum throughput testing, still recommended to use:
- `example.com:80` - actual HTTP server that accepts data
- `1.1.1.1:80` - Cloudflare's anycast, handles high volume
- High-bitrate targets that expect traffic
