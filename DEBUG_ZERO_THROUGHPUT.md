# Zero Throughput Fix - Debug Version

## Changes Made

### 1. Fixed TCP MAX LOAD blocking issue
**Problem**: The `socket.addStream()` call was blocking and preventing the periodic timer from running.

**Fix**: Changed to direct `socket.add()` calls with periodic yields:
```dart
while (isRunning()) {
  socket.add(buffer);
  onBytesSent(buffer.length);
  writeCount++;
  // Yield every 10 writes to let the timer run
  if (writeCount % 10 == 0) {
    await Future.delayed(Duration.zero);
  }
}
```

### 2. Added Extensive Debug Logging

Now you'll see in console:
- `WORKER X timer tick: accumulated=YYYY bytes` - Worker counting bytes
- `WORKER X sent report: YYYY bytes` - Worker sending to main
- `DEBUG: Received report: YYYY bytes` - Main receiving from worker
- `DEBUG TIMER: accumulated=YYYY bytes` - Main aggregating
- `DEBUG TIMER: Emitting sample with XXX bps` - Main emitting to UI

## How to Test

1. **Rebuild and run**:
   ```bash
   flutter run
   ```

2. **Start test** with your router (192.168.1.1:80)

3. **Watch console** - You should now see:
   ```
   === CONNECTIVITY PROBE START ===
   PROBE: Success - endpoint reachable
   === STARTING TRAFFIC ENGINE ===
   DEBUG: Worker SendPort registered (1 total)
   DEBUG: Worker SendPort registered (2 total)
   WORKER 0 resolved host -> 192.168.1.1
   WORKER 0 connected (tcp) -> 192.168.1.1:80
   WORKER 1 resolved host -> 192.168.1.1
   WORKER 1 connected (tcp) -> 192.168.1.1:80
   WORKER 0 timer tick: accumulated=10240 bytes
   WORKER 0 sent report: 10240 bytes
   DEBUG: Received report: 10240 bytes (total accumulated: 10240)
   WORKER 1 timer tick: accumulated=10240 bytes
   WORKER 1 sent report: 10240 bytes
   DEBUG: Received report: 10240 bytes (total accumulated: 20480)
   DEBUG TIMER: accumulated=20480 bytes over 0.5s
   DEBUG TIMER: Emitting sample with 327680.0 bps
   ```

## Expected Results

- Workers should show `accumulated=XXXX bytes` (non-zero) every 500ms
- Main should receive reports and accumulate them
- Timer should emit samples with non-zero bps
- UI chart should show rising throughput

## If Still Zero

Check the console for which step is failing:

### Case 1: Workers show accumulated=0
**Problem**: Socket writes are not executing or blocking
**Debug**: Look for these lines after "WORKER X connected":
- Are you seeing repeated "WORKER X timer tick" lines?
- Is accumulated always 0?

**Possible causes**:
- Router dropped connection after accept
- Socket buffer full and blocking (shouldn't happen with new code)
- onBytesSent callback not firing

### Case 2: Workers show bytes but Main doesn't receive
**Problem**: Message passing between isolates broken
**Debug**: 
- Do you see "WORKER X sent report" but NOT "DEBUG: Received report"?
- This would be very unusual - isolate communication issue

### Case 3: Main receives but Timer doesn't emit
**Problem**: Aggregator timer not running or metrics controller issue
**Debug**:
- Do you see "DEBUG TIMER: accumulated=XXX" with non-zero?
- Do you see "DEBUG TIMER: Emitting sample"?

### Case 4: Timer emits but UI shows zero
**Problem**: UI subscription or chart update issue
**Debug**: Check main.dart metrics listener

## Quick Synthetic Test

To prove the pipeline works without network, temporarily replace the worker loop with:

In `_trafficIsolateEntryPoint`, replace the entire try/catch block with:
```dart
// SYNTHETIC TEST - bypass network
while (running) {
  await Future.delayed(Duration(milliseconds: 100));
  bytesAccumulator += 1024; // fake 1KB sent
}
```

If chart shows throughput with this, the issue is in the socket write loop.
If chart still shows zero, the issue is in the UI/metrics pipeline.

## Next Steps

Run the test and copy/paste these specific lines from console:
1. All lines with "WORKER X timer tick"
2. All lines with "sent report"
3. All lines with "Received report"
4. All lines with "DEBUG TIMER"
5. Any ERROR or exception lines

This will pinpoint exactly where the data flow breaks.
