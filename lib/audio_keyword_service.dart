import 'package:flutter/services.dart';

class AudioKeywordService {
  static const _channel = MethodChannel('audio_keyword/model');
  
  Function(String keyword, double confidence, double inferenceTime)? onKeywordDetected;

  AudioKeywordService() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (call.method == 'onKeywordDetected') {
      final keyword = call.arguments['keyword'] as String;
      final confidence = call.arguments['confidence'] as double;
      final inferenceTime = call.arguments['inferenceTime'] as double;
      
      onKeywordDetected?.call(keyword, confidence, inferenceTime);
    }
  }

  Future<bool> initialize() async {
    try {
      final result = await _channel.invokeMethod('initModel');
      return result == true;
    } catch (e) {
      print('Error initializing audio model: $e');
      return false;
    }
  }

  Future<bool> startListening() async {
    try {
      final result = await _channel.invokeMethod('startListening');
      return result == true;
    } catch (e) {
      print('Error starting listening: $e');
      return false;
    }
  }

  Future<bool> stopListening() async {
    try {
      final result = await _channel.invokeMethod('stopListening');
      return result == true;
    } catch (e) {
      print('Error stopping listening: $e');
      return false;
    }
  }

  void dispose() {
    stopListening();
  }
}