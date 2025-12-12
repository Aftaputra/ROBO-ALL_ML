import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'audio_classifier.dart';  // dari roboice

class AppColors {
  static const Color primary = Color(0xFF4DB6AC);
  static const Color primaryDark = Color(0xFF26A69A);
  static const Color accent = Color(0xFF80CBC4);
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

class _AudioKeywordScreenState extends State<AudioKeywordScreen> {
  AudioClassifier? _classifier;
  
  bool _isInitialized = false;
  bool _isListening = false;
  String _command = "N/A";
  String _statusMessage = "Initializing...";
  double _confidence = 0.0;
  double _inferenceTime = 0.0;
  
  final List<Map<String, dynamic>> _history = [];
  final List<String> _consoleMessages = [];
  final ScrollController _consoleScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    _addConsoleLog('🚀 Initializing audio model...');
    
    // Request permission
    final micStatus = await Permission.microphone.request();
    if (micStatus != PermissionStatus.granted) {
      setState(() {
        _statusMessage = "Microphone permission denied";
        _isInitialized = false;
      });
      _addConsoleLog('❌ Microphone permission denied');
      return;
    }
    _addConsoleLog('✅ Microphone permission granted');

    try {
      _classifier = AudioClassifier(
        onPrediction: (command, predictions, inferenceTime) {
          if (command != "N/A") {
            final topPred = predictions.isNotEmpty ? predictions[0] : null;
            setState(() {
              _command = command;
              _confidence = topPred?.confidence ?? 0.0;
              _inferenceTime = inferenceTime;
              
              _history.insert(0, {
                'keyword': command,
                'confidence':  _confidence,
                'time':  DateTime.now(),
              });
              
              if (_history.length > 10) _history.removeLast();
            });
            
            _addConsoleLog('🎯 Detected:  $command (${(_confidence * 100).toStringAsFixed(1)}%) - ${inferenceTime.toStringAsFixed(0)}ms');
          }
        },
      );

      await _classifier! .initialize();

      setState(() {
        _isInitialized = true;
        _statusMessage = "Ready - Tap to start";
      });
      
      _addConsoleLog('✅ Audio model ready');
    } catch (e) {
      setState(() {
        _statusMessage = "Error:  $e";
        _isInitialized = false;
      });
      _addConsoleLog('❌ Failed to initialize:  $e');
    }
  }

  void _addConsoleLog(String message) {
    setState(() {
      _consoleMessages.add('[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_consoleMessages.length > 30) _consoleMessages.removeAt(0);
    });
    
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_consoleScroll.hasClients) {
        _consoleScroll.animateTo(
          _consoleScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves. easeOut,
        );
      }
    });
  }

  Future<void> _toggleListening() async {
    if (! _isInitialized || _classifier == null) return;

    try {
      if (_isListening) {
        await _classifier!.stopListening();
        setState(() {
          _isListening = false;
          _statusMessage = "Stopped - Tap to start";
          _command = "N/A";
        });
        _addConsoleLog('🛑 Stopped listening');
      } else {
        await _classifier!.startListening();
        setState(() {
          _isListening = true;
          _statusMessage = "Listening... ";
        });
        _addConsoleLog('🎤 Started listening');
      }
    } catch (e) {
      _addConsoleLog('❌ Error:  $e');
    }
  }

  @override
  void dispose() {
    _classifier?. dispose();
    _consoleScroll.dispose();
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
                begin:  Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primaryDark.withOpacity(0.3),
                  Colors.black,
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildMainContent()),
                _buildConsole(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black. withOpacity(0.5),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent, width: 2),
              ),
              child:  const Icon(Icons.arrow_back, color: AppColors.accent, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          const Text('Voice Command', style: TextStyle(color:  Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isInitialized ? AppColors.success. withOpacity(0.2) : AppColors.error.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _isInitialized ? AppColors. success : AppColors.error, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_isInitialized ? Icons.check_circle : Icons.error, color: _isInitialized ? AppColors.success : AppColors.error, size: 16),
                const SizedBox(width: 6),
                Text(_isInitialized ? 'Ready' : 'Error', style: TextStyle(color: _isInitialized ? AppColors.success : AppColors.error, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment. center,
        children: [
          Text(_statusMessage, style: const TextStyle(color: AppColors.accent, fontSize: 14)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _isInitialized ? _toggleListening :  null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: _isListening ? AppColors.error. withOpacity(0.2) : AppColors.primary.withOpacity(0.2),
                shape: BoxShape. circle,
                border: Border. all(color: _isListening ? AppColors.error : AppColors.primary, width: 4),
                boxShadow: _isListening ? [BoxShadow(color: AppColors.error. withOpacity(0.5), blurRadius: 20, spreadRadius: 5)] : [],
              ),
              child: Icon(_isListening ? Icons.stop : Icons.mic, color: _isListening ? AppColors.error : AppColors.primary, size: 50),
            ),
          ),
          const SizedBox(height:  32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors. cardBackground. withOpacity(0.1),
              borderRadius: BorderRadius. circular(16),
              border: Border.all(color: _command != "N/A" ? AppColors.success : AppColors.accent. withOpacity(0.3), width: 2),
            ),
            child: Column(
              children: [
                const Text('Detected Command', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Text(_command. toUpperCase(), style: TextStyle(color: _command != "N/A" ?  AppColors.success : Colors.white54, fontSize: 36, fontWeight: FontWeight.bold)),
                if (_command != "N/A") ...[
                  const SizedBox(height: 8),
                  Text('${(_confidence * 100).toStringAsFixed(1)}% • ${_inferenceTime.toStringAsFixed(0)}ms', style: const TextStyle(color: AppColors. accent, fontSize: 14)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_history.isNotEmpty) _buildHistory(),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _history.length,
        itemBuilder: (context, index) {
          final item = _history[index];
          final isRecent = index == 0;
          return Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isRecent ? AppColors.primary.withOpacity(0.2) : Colors.white. withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isRecent ? AppColors.primary :  AppColors.accent. withOpacity(0.3), width: isRecent ? 2 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(item['keyword']. toString().toUpperCase(), style: TextStyle(color: isRecent ?  AppColors.primary : Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${((item['confidence'] as double) * 100).toStringAsFixed(0)}%', style: TextStyle(color: isRecent ? AppColors.accent : Colors.white38, fontSize: 11)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConsole() {
    return Container(
      height: 120,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent. withOpacity(0.5), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, color: AppColors.accent, size: 14),
              const SizedBox(width: 6),
              const Text('Console', style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _consoleMessages.clear()),
                child: const Icon(Icons.clear_all, color: AppColors.accent, size: 14),
              ),
            ],
          ),
          const Divider(color: AppColors. accent, height: 12),
          Expanded(
            child: ListView.builder(
              controller: _consoleScroll,
              itemCount: _consoleMessages.length,
              itemBuilder: (ctx, i) => Text(_consoleMessages[i], style:  const TextStyle(color: AppColors.accent, fontSize: 9, fontFamily: 'monospace')),
            ),
          ),
        ],
      ),
    );
  }
}