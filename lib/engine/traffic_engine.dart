import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Protocols supported by the TrafficEngine
enum TrafficProtocol { tcp, udp }

/// Configuration for the load target
class TargetConfig {
  final String host;
  final int port;
  final TrafficProtocol protocol;
  /// Target bitrate in bits per second. 0 means maximum possible speed.
  final int bitrateBps; 
  final int numThreads;
  final int packetSize;
  /// Duration of the load test in seconds. 0 or null means infinite.
  final int durationSeconds;

  const TargetConfig({
    required this.host,
    required this.port,
    required this.protocol,
    this.bitrateBps = 0,
    this.numThreads = 2,
    this.packetSize = 1024,
    this.durationSeconds = 0,
  });
}

/// A sample of traffic metrics
class MetricSample {
  final DateTime timestamp;
  final int bytesSentDelta;
  final double bitsPerSecond;

  MetricSample({
    required this.timestamp,
    required this.bytesSentDelta,
    required this.bitsPerSecond,
  });

  @override
  String toString() => 'MetricSample(bps: ${bitsPerSecond.toStringAsFixed(1)}, bytesDelta: $bytesSentDelta)';
}

/// Engine Status
enum EngineStatus { stopped, running }

// Private classes for Isolate communication
class _IsolateConfig {
  final TargetConfig target;
  final SendPort sendPort;
  final int threadIndex;

  _IsolateConfig(this.target, this.sendPort, this.threadIndex);
}

class _Report {
  final int bytesSent;
  _Report(this.bytesSent);
}

class _Error {
  final String message;
  _Error(this.message);
}

class TrafficEngine {
  final List<Isolate> _isolates = [];
  final List<SendPort> _isolateSendPorts = [];
  
  final StreamController<MetricSample> _metricsController = StreamController<MetricSample>.broadcast();
  Stream<MetricSample> get metrics => _metricsController.stream;

  final StreamController<EngineStatus> _statusController = StreamController<EngineStatus>.broadcast();
  Stream<EngineStatus> get status => _statusController.stream;

  bool _isRunning = false;
  
  // Aggregation state
  Timer? _aggregatorTimer;
  Timer? _autoStopTimer;
  int _accumulatedBytesInterval = 0;
  DateTime _lastSampleTime = DateTime.now();

  /// Start the load with the given configuration
  Future<void> startLoad(TargetConfig cfg) async {
    if (_isRunning) throw Exception("Load already running");
    _isRunning = true;
    _statusController.add(EngineStatus.running);
    
    _lastSampleTime = DateTime.now();
    _accumulatedBytesInterval = 0;

    // Auto-stop timer
    if (cfg.durationSeconds > 0) {
      _autoStopTimer = Timer(Duration(seconds: cfg.durationSeconds), () {
        stopLoad();
      });
    }

    // Start aggregation timer (500ms)
    // This timer collects reports from all isolates and emits a MetricSample
    _aggregatorTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final now = DateTime.now();
      final durationSeconds = now.difference(_lastSampleTime).inMicroseconds / 1000000.0;
      
      print('DEBUG TIMER: accumulated=${_accumulatedBytesInterval} bytes over ${durationSeconds}s');
      
      if (durationSeconds > 0) {
        final bps = (_accumulatedBytesInterval * 8) / durationSeconds;
        print('DEBUG TIMER: Emitting sample with $bps bps');
        _metricsController.add(MetricSample(
          timestamp: now,
          bytesSentDelta: _accumulatedBytesInterval,
          bitsPerSecond: bps,
        ));
      }
      
      _accumulatedBytesInterval = 0;
      _lastSampleTime = now;
    });

    try {
      for (int i = 0; i < cfg.numThreads; i++) {
        final receivePort = ReceivePort();
        
        final isolate = await Isolate.spawn(
          _trafficIsolateEntryPoint,
          _IsolateConfig(cfg, receivePort.sendPort, i),
        );
        
        _isolates.add(isolate);
        
        receivePort.listen((message) {
          if (message is Map) {
            final ev = message['event'];
            if (ev == 'worker_connected') {
              print('WORKER ${message['worker']} connected (${message['type']}) -> ${message['remote']}');
            } else if (ev == 'resolved') {
              print('WORKER ${message['worker']} resolved host -> ${message['addr']}');
            } else if (ev == 'worker_error') {
              print('WORKER ERROR ${message['worker']}: ${message['error']}');
              // optional: send this to UI via metricsStream or an error stream
            }
            return;
          }
          if (message is SendPort) {
            _isolateSendPorts.add(message);
            print('DEBUG: Worker SendPort registered (${_isolateSendPorts.length} total)');
          } else if (message is _Report) {
            _accumulatedBytesInterval += message.bytesSent;
            print('DEBUG: Received report: ${message.bytesSent} bytes (total accumulated: $_accumulatedBytesInterval)');
          } else if (message is _Error) {
             print("TrafficEngine Isolate Error: ${message.message}");
             // We can choose to stop or just report error
             // _metricsController.addError(message.message);
          }
        });
      }
    } catch (e) {
      emergencyStop();
      rethrow;
    }
  }

  /// Gracefully stop the load
  Future<void> stopLoad() async {
    if (!_isRunning) return;
    
    // Send stop signal to all isolates
    for (var port in _isolateSendPorts) {
      port.send('stop');
    }
    
    _finish();
  }

  /// Immediately kill all isolates
  void emergencyStop() {
    for (var isolate in _isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _finish();
  }
  
  void _finish() {
    _isRunning = false;
    _aggregatorTimer?.cancel();
    _aggregatorTimer = null;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    _isolates.clear();
    _isolateSendPorts.clear();
    _statusController.add(EngineStatus.stopped);
  }

  void dispose() {
    emergencyStop();
    _metricsController.close();
    _statusController.close();
  }
}

// ---------------------- ISOLATE LOGIC ----------------------

void _trafficIsolateEntryPoint(_IsolateConfig config) async {
  final commandReceivePort = ReceivePort();
  config.sendPort.send(commandReceivePort.sendPort); 

  final target = config.target;
  bool running = true;
  int bytesAccumulator = 0;

  commandReceivePort.listen((message) {
    if (message == 'stop') {
      running = false;
    }
  });

  Timer.periodic(const Duration(milliseconds: 500), (t) {
    if (bytesAccumulator > 0) {
      config.sendPort.send(_Report(bytesAccumulator));
      bytesAccumulator = 0;
    }
    if (!running) {
      t.cancel();
      Isolate.exit();
    }
  });

  // For TCP max load, we want a HUGE buffer to minimize overhead (1MB).
  // For UDP, we use the maximum safe UDP payload (65507 bytes) to maximize throughput per syscall.
  // This forces IP fragmentation which is excellent for stress testing routers.
  
  final tcpChunkSize = 1024 * 1024; // 1MB
  final tcpBuffer = Uint8List(tcpChunkSize);
  // Fill with some data
  for (int i = 0; i < tcpChunkSize; i+=1024) tcpBuffer[i] = i & 0xFF;

  final udpBufferSize = 65507;
  final udpBuffer = Uint8List(udpBufferSize);
  for (int i = 0; i < udpBufferSize; i+=1024) udpBuffer[i] = i & 0xFF;

  try {
    if (target.protocol == TrafficProtocol.tcp) {
      await _runTcpLoad(target, tcpBuffer, () => running, (sent) => bytesAccumulator += sent, config.sendPort, config.threadIndex);
    } else {
      await _runUdpLoad(target, udpBuffer, () => running, (sent) => bytesAccumulator += sent, config.sendPort, config.threadIndex);
    }
  } catch (e, st) {
    config.sendPort.send({'event': 'worker_error', 'worker': config.threadIndex, 'error': e.toString(), 'stack': st.toString()});
    config.sendPort.send(_Error(e.toString()));
  } finally {
    running = false; 
  }
}

Future<void> _runTcpLoad(
  TargetConfig target, 
  Uint8List buffer, 
  bool Function() isRunning, 
  Function(int) onBytesSent,
  SendPort master,
  int workerId
) async {
  Socket? socket;
  try {
    final addresses = await InternetAddress.lookup(target.host);
    if (addresses.isEmpty) throw Exception("Could not resolve ${target.host}");
    final addr = addresses.first;
    master.send({'event': 'resolved', 'worker': workerId, 'addr': addr.address});

    // Timeout of 5 seconds to fail fast
    socket = await Socket.connect(addr, target.port, timeout: const Duration(seconds: 5));
    
    // Nagle's off for lower latency initial sends?
    socket.setOption(SocketOption.tcpNoDelay, true); 

    master.send({'event': 'worker_connected', 'worker': workerId, 'type': 'tcp', 'remote': '${addr.address}:${target.port}'});
    
    if (target.bitrateBps == 0) {
      // MAX LOAD: Use addStream to respect backpressure and avoid OOM.
      // Creating a stream of the buffer repeatedly.
      Stream<List<int>> trafficGenerator() async* {
        while (isRunning()) {
          onBytesSent(buffer.length);
          yield buffer;
        }
      }
      // This will pipe data until generator stops (when isRunning is false) or socket closes
      await socket.addStream(trafficGenerator());
      
    } else {
      // PACED LOAD
      final targetBps = target.bitrateBps / target.numThreads;
      final targetBytesPerSec = targetBps / 8;
      
      await _pacingLoop(targetBytesPerSec, buffer.length, isRunning, () {
         socket!.add(buffer);
         onBytesSent(buffer.length);
      });
    }
  } catch(e, st) {
     master.send({'event': 'worker_error', 'worker': workerId, 'error': e.toString(), 'stack': st.toString()});
     throw e;
  } finally {
    socket?.destroy();
  }
}

Future<void> _runUdpLoad(
  TargetConfig target, 
  Uint8List buffer, 
  bool Function() isRunning, 
  Function(int) onBytesSent,
  SendPort master,
  int workerId
) async {
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final addresses = await InternetAddress.lookup(target.host);
    if (addresses.isEmpty) throw Exception("Could not resolve ${target.host}");
    final destAddr = addresses.first;
    final destPort = target.port;
    
    master.send({'event': 'resolved', 'worker': workerId, 'addr': destAddr.address});
    master.send({'event': 'worker_connected', 'worker': workerId, 'type': 'udp', 'remote': '${destAddr.address}:${destPort}'});

    if (target.bitrateBps == 0) {
      // MAX LOAD UDP
      int ops = 0;
      while (isRunning()) {
        final sent = socket.send(buffer, destAddr, destPort);
        if (sent > 0) {
           onBytesSent(sent);
           ops++;
           // Yield every 100 huge packets (~6.5MB) to keep UI/Timer responsive
           if (ops % 100 == 0) await Future.delayed(Duration.zero);
        } else {
           // Buffer full or error. Yield to let OS flush.
           await Future.delayed(Duration.zero);
        }
      }
    } else {
      // PACED LOAD UDP
      final targetBps = target.bitrateBps / target.numThreads;
      final targetBytesPerSec = targetBps / 8;
      
      await _pacingLoop(targetBytesPerSec, buffer.length, isRunning, () {
         final sent = socket!.send(buffer, destAddr, destPort);
         if (sent > 0) onBytesSent(sent);
      });
    }

  } catch (e, st) {
    master.send({'event': 'worker_error', 'worker': workerId, 'error': e.toString(), 'stack': st.toString()});
    throw e;
  } finally {
    socket?.close();
  }
}

Future<void> _pacingLoop(
  double targetBytesPerSec, 
  int packetSize, 
  bool Function() isRunning,
  Function() sendAction
) async {
  final microsecPerPacket = (packetSize / targetBytesPerSec * 1000000).toInt();
  
  while (isRunning()) {
    final start = DateTime.now();
    sendAction();
    final end = DateTime.now();
    
    final elapsed = end.difference(start).inMicroseconds;
    final wait = microsecPerPacket - elapsed;
    
    if (wait > 0) {
      if (wait > 1000) {
         await Future.delayed(Duration(microseconds: wait));
      } else {
         await Future.delayed(Duration.zero);
      }
    } else {
      await Future.delayed(Duration.zero); 
    }
  }
}
