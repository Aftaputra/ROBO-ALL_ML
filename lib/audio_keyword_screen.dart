import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class AppColors {
  static const Color primary = Color(0xFF4DB6AC);
  static const Color primaryDark = Color(0xFF26A69A);
  static const Color accent = Color(0xFF80CBC4);
  static const Color background = Color(0xFFF5F5F5);
  static const Color cardBackground = Color(0xFFE0F2F1);
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
}

class AudioKeywordScreen extends StatefulWidget {
  const AudioKeywordScreen({super.key});

  @override
  State<AudioKeywordScreen> createState() => _AudioKeywordScreenState();
}

class _AudioKeywordScreenState extends State<AudioKeywordScreen> with TickerProviderStateMixin {
  static const platform = MethodChannel('audio_keyword/model');
  
  bool _isListening = false;
  bool _modelLoaded = false;
  String _lastKeyword = '';
  double _lastConfidence = 0.0;
  double _lastInferenceTime = 0.0;
  
  final List<String> _consoleMessages = [];
  final ScrollController _consoleScroll = ScrollController();
  bool _showConsole = true;
  
  late AnimationController _waveController;
  final List<double> _waveHeights = List.generate(40, (i) => 0.3);
  Timer? _waveTimer;
  
  final List<String> _keywords = ['robodu', 'perkenalan', 'kanan', 'kiri', 'maju', 'mundur'];
  
  final Map<String, Color> _keywordColors = {
    'robodu': AppColors.primary,
    'perkenalan': Colors.purple,
    'kanan': Colors.blue,
    'kiri': Colors.orange,
    'maju': AppColors.success,
    'mundur': AppColors.error,
  };

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _init();
  }

  Future<void> _init() async {
    _addConsoleLog('Initializing audio keyword spotting...');
    await Permission.microphone.request();
    await _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final result = await platform.invokeMethod('initModel');
      if (mounted) {
        setState(() => _modelLoaded = result == true);
        _addConsoleLog('Model loaded successfully');
      }
    } catch (e) {
      if (mounted) _addConsoleLog('Model error: $e');
    }
  }

  void _addConsoleLog(String message) {
    if (!mounted) return;
    
    setState(() {
      _consoleMessages.add('[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_consoleMessages.length > 50) _consoleMessages.removeAt(0);
    });
    
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _consoleScroll.hasClients) {
        _consoleScroll.animateTo(
          _consoleScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    try {
      await platform.invokeMethod('startListening');
      if (mounted) {
        setState(() => _isListening = true);
        _addConsoleLog('Listening started...');
      }
      
      _waveTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_isListening && mounted) {
          setState(() {
            for (int i = 0; i < _waveHeights.length; i++) {
              _waveHeights[i] = 0.2 + (0.8 * (i % 3 == 0 ? 0.5 : 1.0)) * (0.5 + 0.5 * math.sin(DateTime.now().millisecond / 100 + i));
            }
          });
        }
      });
      
      platform.setMethodCallHandler((call) async {
        if (call.method == 'onKeywordDetected' && mounted) {
          final keyword = call.arguments['keyword'] as String;
          final confidence = (call.arguments['confidence'] as num).toDouble();
          final inferenceTime = (call.arguments['inferenceTime'] as num).toDouble();
          
          setState(() {
            _lastKeyword = keyword;
            _lastConfidence = confidence;
            _lastInferenceTime = inferenceTime;
          });
          
          _addConsoleLog('$keyword (${(confidence * 100).toStringAsFixed(1)}%) | ${inferenceTime.toStringAsFixed(1)}ms');
        }
      });
      
    } catch (e) {
      if (mounted) _addConsoleLog('Start listening error: $e');
    }
  }

  Future<void> _stopListening() async {
    try {
      await platform.invokeMethod('stopListening');
      _waveTimer?.cancel();
      
      if (mounted) {
        setState(() => _isListening = false);
        _addConsoleLog('Listening stopped');
      }
    } catch (e) {
      if (mounted) _addConsoleLog('Stop listening error: $e');
    }
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    _waveController.dispose();
    _consoleScroll.dispose();
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black,
                  AppColors.primaryDark.withOpacity(0.3),
                  Colors.black,
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildMainContent()),
                if (_showConsole) _buildConsole(),
              ],
            ),
          ),
          _buildFloatingControls(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent, width: 2),
              ),
              child: const Icon(Icons.arrow_back, color: AppColors.accent, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Voice Commands',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _modelLoaded ? 'Model Ready' : 'Loading...',
                  style: TextStyle(
                    fontSize: 12,
                    color: _modelLoaded ? AppColors.success : AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isListening ? AppColors.success : Colors.grey,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isListening ? 'LIVE' : 'OFF',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

Widget _buildMainContent() {
  return SingleChildScrollView(  // TAMBAH INI
    child: ConstrainedBox(  // TAMBAH INI
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height - 250,  // TAMBAH INI
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildWaveform(),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: _toggleListening,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isListening ? AppColors.success : AppColors.primary,
                boxShadow: _isListening
                    ? [
                        BoxShadow(
                          color: AppColors.success.withOpacity(0.5),
                          blurRadius: 30,
                          spreadRadius: 10,
                        )
                      ]
                    : [],
              ),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                size: 60,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _isListening ? 'Listening...' : 'Tap to start',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withOpacity(0.8),
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 40),
          if (_lastKeyword.isNotEmpty) _buildLastDetection(),
          const SizedBox(height: 32),
          _buildKeywordsGrid(),
          const SizedBox(height: 20), // TAMBAH padding bawah
        ],
      ),
    ),
  );
}
  Widget _buildWaveform() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(40, (i) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 3,
            height: _isListening ? _waveHeights[i] * 80 : 20,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.8),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLastDetection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      margin: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: AppColors.cardBackground.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _keywordColors[_lastKeyword] ?? AppColors.accent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle,
                color: _keywordColors[_lastKeyword],
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                _lastKeyword.toUpperCase(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _keywordColors[_lastKeyword],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Confidence: ${(_lastConfidence * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${_lastInferenceTime.toStringAsFixed(1)}ms',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeywordsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keywords',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.7),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _keywords.map((keyword) {
              final isActive = _lastKeyword == keyword;
              final color = _keywordColors[keyword] ?? AppColors.accent;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? color.withOpacity(0.3)
                      : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive ? color : Colors.white.withOpacity(0.3),
                    width: isActive ? 2 : 1,
                  ),
                ),
                child: Text(
                  keyword,
                  style: TextStyle(
                    color: isActive ? color : Colors.white.withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildConsole() {
    return Container(
      height: 150,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, color: AppColors.accent, size: 16),
              const SizedBox(width: 6),
              const Text(
                'Console',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() {
                  _consoleMessages.clear();
                  _addConsoleLog('Console cleared');
                }),
                child: const Icon(Icons.clear_all, color: AppColors.accent, size: 16),
              ),
            ],
          ),
          const Divider(color: AppColors.accent, height: 16),
          Expanded(
            child: ListView.builder(
              controller: _consoleScroll,
              itemCount: _consoleMessages.length,
              itemBuilder: (ctx, i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _consoleMessages[i],
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingControls() {
    return Positioned(
      right: 16,
      bottom: _showConsole ? 180 : 30,
      child: GestureDetector(
        onTap: () => setState(() => _showConsole = !_showConsole),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accent, width: 2),
          ),
          child: Icon(
            _showConsole ? Icons.keyboard_arrow_down : Icons.terminal,
            color: AppColors.accent,
            size: 24,
          ),
        ),
      ),
    );
  }
}