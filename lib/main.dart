import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'engine/traffic_engine.dart';

void main() {
  runApp(const WifiStressApp());
}

class WifiStressApp extends StatelessWidget {
  const WifiStressApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi Stress Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFFBB86FC),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFBB86FC),
          secondary: Color(0xFF03DAC6),
          error: Color(0xFFCF6679),
          surface: Color(0xFF1E1E1E),
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2C2C2C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          labelStyle: const TextStyle(color: Colors.grey),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
        ),
      ),
      home: const StressHomePage(),
    );
  }
}

class StressHomePage extends StatefulWidget {
  const StressHomePage({super.key});

  @override
  State<StressHomePage> createState() => _StressHomePageState();
}

class _StressHomePageState extends State<StressHomePage> {
  Future<bool> probeTcpEndpoint(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      print('PROBE: Starting probe to $host:$port');
      
      final addresses = await InternetAddress.lookup(host).timeout(
        timeout,
        onTimeout: () => throw TimeoutException('DNS lookup timed out'),
      );
      
      if (addresses.isEmpty) {
        print('PROBE FAILED: Could not resolve $host (no addresses)');
        return false;
      }
      
      final addr = addresses.first;
      print('PROBE: Resolved $host -> ${addr.address}');
      
      final socket = await Socket.connect(addr, port, timeout: timeout);
      print('PROBE: Connected to ${addr.address}:$port');
      
      // Send a small test payload
      socket.add(utf8.encode('PING\r\n'));
      await socket.flush();
      print('PROBE: Write succeeded');
      
      // Clean up
      await socket.close();
      print('PROBE: Success - endpoint reachable');
      return true;
    } on SocketException catch (e) {
      print('PROBE FAILED (SocketException): $e');
      return false;
    } on TimeoutException catch (e) {
      print('PROBE FAILED (Timeout): $e');
      return false;
    } catch (e, st) {
      print('PROBE FAILED: $e');
      print('Stack trace: ${st.toString().split('\n').take(3).join('\n')}');
      return false;
    }
  }
  final TrafficEngine _engine = TrafficEngine();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '80');
  final TextEditingController _bitrateController = TextEditingController(text: '0');
  final TextEditingController _durationController = TextEditingController(text: '0');
  
  TrafficProtocol _protocol = TrafficProtocol.udp;
  int _numThreads = 2;
  
  bool _isRunning = false;
  bool _consentGiven = false;
  
  // Chart Data
  final List<FlSpot> _throughputSpots = [];
  final int _maxDataPoints = 120;
  
  StreamSubscription? _metricsSub;
  StreamSubscription? _statusSub;
  Timer? _uiTimer;
  int _accumBytesSinceLast = 0;
  
  double _currentMbps = 0;
  double _xValueCounter = 0;
  
  String? _gatewayStatusMsg;

  @override
  void initState() {
    super.initState();
    
    // Status Listener
    _statusSub = _engine.status.listen((status) {
       setState(() {
         _isRunning = (status == EngineStatus.running);
       });
    });

    // Sub to raw metrics
    _metricsSub = _engine.metrics.listen((sample) {
      _accumBytesSinceLast += sample.bytesSentDelta;
    }, onError: (err) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stream Error: $err')));
    });

    // UI Timer (500ms)
    _uiTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
       final bytes = _accumBytesSinceLast;
       _accumBytesSinceLast = 0;
       
       if (!_isRunning && bytes == 0 && _currentMbps == 0) return;

       final mbps = (bytes * 8 * 2) / 1000000.0;
       
       if (mounted) {
         setState(() {
           _currentMbps = mbps;
           _xValueCounter += 0.5;
           _throughputSpots.add(FlSpot(_xValueCounter, _currentMbps));
           if (_throughputSpots.length > _maxDataPoints) {
             _throughputSpots.removeAt(0);
           }
         });
       }
    });

    _autoFillGateway(); 
  }

  Future<void> _autoFillGateway() async {
    setState(() => _gatewayStatusMsg = "Detecting gateway...");
    try {
      if (Platform.isAndroid) {
        final status = await Permission.location.request();
        if (!status.isGranted) {
           setState(() => _gatewayStatusMsg = "Location permission denied - Enter IP manually");
           return;
        }
      }
      final info = NetworkInfo();
      final gateway = await info.getWifiGatewayIP();
      if (gateway != null && gateway.isNotEmpty && gateway != "0.0.0.0") {
        setState(() {
           _ipController.text = gateway;
           _gatewayStatusMsg = null; 
        });
        return;
      }
      
      // Fallback
      final localIp = await info.getWifiIP();
      if (localIp != null && localIp.isNotEmpty) {
        final parts = localIp.split('.');
        if (parts.length == 4) {
          final gw = '${parts[0]}.${parts[1]}.${parts[2]}.1';
          setState(() { 
             _ipController.text = gw;
             _gatewayStatusMsg = "Auto-estimated gateway (verify if incorrect)";
          });
          return;
        }
      }
      setState(() => _gatewayStatusMsg = "Auto-detect failed - Enter IP manually");
    } catch (_) {
       setState(() => _gatewayStatusMsg = "Auto-detect error - Enter IP manually");
    }
  }

  @override
  void dispose() {
    _metricsSub?.cancel();
    _statusSub?.cancel();
    _uiTimer?.cancel();
    _engine.dispose();
    _ipController.dispose();
    _portController.dispose();
    _bitrateController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  void _resetChart() {
    setState(() {
      _throughputSpots.clear();
      _currentMbps = 0;
      _xValueCounter = 0;
    });
  }

  void _showConsentDialog() {
    final TextEditingController consentController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text('Safety Warning', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This tool generates high-volume network traffic. You must own or have explicit permission to test the target network.\n\nType "I OWN THIS NETWORK" to proceed.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: consentController,
              decoration: const InputDecoration(
                hintText: 'I OWN THIS NETWORK',
                fillColor: Color(0xFF1E1E1E),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              if (consentController.text == 'I OWN THIS NETWORK') {
                setState(() => _consentGiven = true);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Warning accepted. Proceed with caution.')),
                );
              } else {
                 ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Incorrect confirmation text.')),
                );
              }
            },
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );
  }

  Future<void> _startLoad() async {
    // Validate
    if (_ipController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter Target IP')));
      return;
    }
    final port = int.tryParse(_portController.text);
    if (port == null || port <= 0 || port > 65535) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid Port')));
       return;
    }
    final bitrate = int.tryParse(_bitrateController.text);
    if (bitrate == null || bitrate < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid Bitrate')));
      return;
    }
    final duration = int.tryParse(_durationController.text);
    if (duration == null || duration < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid Duration')));
      return;
    }

    _resetChart();

    // Quick connectivity check
    try {
      final testConn = await Socket.connect('1.1.1.1', 80, timeout: Duration(seconds: 3));
      testConn.destroy();
      print('DIAGNOSTIC: Basic internet connectivity OK');
    } catch (e) {
      print('DIAGNOSTIC WARNING: No basic internet connectivity - $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Warning: Internet connectivity issue detected. Check Wi-Fi connection.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    try {
      print('=== CONNECTIVITY PROBE START ===');
      final ok = await probeTcpEndpoint(_ipController.text.trim(), port);
      print('=== PROBE RESULT: $ok ===');
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Target unreachable: ${_ipController.text.trim()}:$port\n\nTry: example.com:80 or 1.1.1.1:80'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
      print('=== STARTING TRAFFIC ENGINE ===');
      await _engine.startLoad(TargetConfig(
        host: _ipController.text.trim(),
        port: port,
        protocol: _protocol,
        bitrateBps: bitrate * 1000, 
        numThreads: _numThreads,
        durationSeconds: duration,
      ));
    } catch (e) {
      print('=== START LOAD ERROR: $e ===');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start: $e')));
    }
  }

  Future<void> _stopLoad() async {
    await _engine.stopLoad();
    _resetChart();
  }

  void _emergencyStop() {
    _engine.emergencyStop();
    _accumBytesSinceLast = 0; 
    _resetChart();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('EMERGENCY STOP TRIGGERED')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TrafficEngine'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TARGET CONFIGURATION', 
                        style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5)
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _ipController,
                        enabled: !_isRunning,
                        decoration: InputDecoration(
                          labelText: 'Target IP / Host',
                          helperText: _gatewayStatusMsg,
                          helperStyle: _gatewayStatusMsg?.contains('failed') == true || _gatewayStatusMsg?.contains('denied') == true 
                            ? const TextStyle(color: Colors.orange) 
                            : const TextStyle(color: Colors.grey),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: _isRunning ? null : _autoFillGateway,
                            tooltip: 'Retry Auto-Detect',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            icon: Icon(Icons.science, size: 16),
                            label: Text('Test: example.com:80'),
                            onPressed: _isRunning ? null : () {
                              setState(() {
                                _ipController.text = 'example.com';
                                _portController.text = '80';
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Responsive row: Port | Protocol | Threads
                      Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: _portController,
                              enabled: !_isRunning,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Port'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<TrafficProtocol>(
                              isExpanded: true,
                              value: _protocol,
                              items: TrafficProtocol.values
                                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name.toUpperCase())))
                                  .toList(),
                              onChanged: _isRunning ? null : (v) => setState(() => _protocol = v ?? TrafficProtocol.udp),
                              decoration: const InputDecoration(labelText: 'Protocol', helperText: 'UDP recommended'),
                              dropdownColor: const Color(0xFF2C2C2C),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 110,
                            child: DropdownButtonFormField<int>(
                              isExpanded: true,
                              value: _numThreads,
                              items: [1, 2, 4, 8]
                                  .map((i) => DropdownMenuItem(value: i, child: Text('$i Threads')))
                                  .toList(),
                              onChanged: _isRunning ? null : (v) => setState(() => _numThreads = v ?? 1),
                              decoration: const InputDecoration(labelText: 'Threads'),
                              dropdownColor: const Color(0xFF2C2C2C),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row( 
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _bitrateController,
                              enabled: !_isRunning,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Bitrate (kbps)',
                                helperText: '0 = Unlimited',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _durationController,
                              enabled: !_isRunning,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Duration (sec)',
                                helperText: '0 = Infinite',
                              ),
                            ),
                          ),
                        ]
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // --- CHART ---
              Container(
                height: 250,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                         Text('LIVE THROUGHPUT', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                         Text('${_currentMbps.toStringAsFixed(2)} Mbps', 
                           style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 18)
                         ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: LineChart(
                        LineChartData(
                          gridData: FlGridData(
                            show: true, 
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
                          ),
                          titlesData: FlTitlesData(
                             leftTitles: AxisTitles(
                               sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)))
                             ),
                             bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                             rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                             topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          minX: _throughputSpots.isEmpty ? 0 : _throughputSpots.first.x,
                          maxX: (_throughputSpots.isEmpty ? 0 : _throughputSpots.first.x) + (_maxDataPoints * 0.5), 
                          minY: 0,
                          lineBarsData: [
                            LineChartBarData(
                              spots: _throughputSpots,
                              isCurved: true,
                              color: primary,
                              barWidth: 3,
                              dotData: FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: primary.withOpacity(0.2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // --- CONTROLS ---
              if (!_consentGiven)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.redAccent.withOpacity(0.1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Safety verification required to enable load generation.')),
                      TextButton(
                        onPressed: _showConsentDialog,
                        child: const Text('UNLOCK', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                ),
                
              const SizedBox(height: 16),
              
              Row(
                children: [
                   Expanded(
                     child: SizedBox(
                       height: 56,
                       child: ElevatedButton(
                         onPressed: (!_consentGiven || _isRunning) ? null : _startLoad,
                         style: ElevatedButton.styleFrom(
                           backgroundColor: const Color(0xFF03DAC6),
                           foregroundColor: Colors.black,
                         ),
                         child: const Text('START LOAD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                       ),
                     ),
                   ),
                   const SizedBox(width: 16),
                   Expanded(
                     child: SizedBox(
                       height: 56,
                       child: ElevatedButton(
                         onPressed: _isRunning ? _stopLoad : null,
                         style: ElevatedButton.styleFrom(
                           backgroundColor: const Color(0xFFCF6679),
                           foregroundColor: Colors.black,
                         ),
                         child: const Text('STOP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                       ),
                     ),
                   ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _emergencyStop,
                  icon: const Icon(Icons.back_hand, color: Colors.red),
                  label: const Text('EMERGENCY KILL SWITCH', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                   style: OutlinedButton.styleFrom(
                     padding: const EdgeInsets.symmetric(vertical: 16),
                     side: const BorderSide(color: Colors.red, width: 2),
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                   ),
                ),
              ),
              
              const SizedBox(height: 24),
              const Center(child: Text('TrafficEngine v1.0 • Pure Dart Isolate Kernel', style: TextStyle(color: Colors.white24))),
            ],
          ),
        ),
      ),
    );
  }
}
