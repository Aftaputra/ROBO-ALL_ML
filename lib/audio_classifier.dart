import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'feature_extractor.dart';
import 'tflite_helper.dart';

class PredictionResult {
  final String label;
  final double confidence;
  PredictionResult(this.label, this.confidence);
}

class AudioClassifier {
  static const String modelPath = 'assets/robodu.tflite';
  static const List<String> labels = [
    "kanan", "kiri", "maju", "mundur", "noise", "perkenalan", "robodu", "unknown"
  ];

  static const int sampleRate = 16000;
  static const double inferInterval = 0.2;
  static const double inferWindowDuration = 1.0;
  static const double confThreshold = 0.35; // Turunkan dari 0.7 ke 0.35

  TFLiteHelper?  _tfliteHelper;
  FlutterSoundRecorder? _recorder;
  Timer? _inferenceTimer;

  final List<int> _audioBuffer = [];
  final Function(String, List<PredictionResult>, double) onPrediction;

  String? _recordingPath;
  int _lastFileSize = 0;
  bool _isProcessing = false;

  AudioClassifier({required this.onPrediction});

  Future<void> initialize() async {
    try {
      _tfliteHelper = TFLiteHelper();
      await _tfliteHelper!.loadModel(modelPath);

      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();

      print('Classifier initialized successfully');
    } catch (e) {
      print('Error initializing: $e');
      rethrow;
    }
  }

  Future<void> startListening() async {
    if (_recorder == null) throw Exception('Recorder not initialized');

    _audioBuffer.clear();
    _lastFileSize = 0;
    _isProcessing = false;

    final directory = await getTemporaryDirectory();
    _recordingPath = '${directory.path}/temp_recording.wav';

    final file = File(_recordingPath!);
    if (await file.exists()) {
      await file.delete();
    }

    await _recorder!. startRecorder(
      toFile: _recordingPath,
      codec: Codec.pcm16WAV,
      sampleRate: sampleRate,
      numChannels: 1,
    );

    print('Recording started');

    _inferenceTimer = Timer. periodic(
      Duration(milliseconds: (inferInterval * 1000).toInt()),
      (_) => _processRecording(),
    );
  }

  Future<void> _processRecording() async {
    if (_recordingPath == null || _isProcessing) return;
    _isProcessing = true;

    try {
      final file = File(_recordingPath!);
      if (! await file.exists()) {
        _isProcessing = false;
        return;
      }

      final fileStat = await file.stat();
      final currentSize = fileStat.size;

      if (currentSize <= _lastFileSize || currentSize <= 44) {
        _isProcessing = false;
        return;
      }

      final bytes = await file.readAsBytes();
      final startPos = _lastFileSize > 44 ? _lastFileSize : 44;
      final newData = bytes.sublist(startPos);

      if (newData.isEmpty) {
        _isProcessing = false;
        return;
      }

      final byteData = ByteData.sublistView(newData);

      for (int i = 0; i < byteData.lengthInBytes - 1; i += 2) {
        _audioBuffer.add(byteData.getInt16(i, Endian.little));
      }

      _lastFileSize = currentSize;

      final windowSamples = (sampleRate * inferWindowDuration). toInt();

      if (_audioBuffer.length >= windowSamples) {
        final audioWindow = _audioBuffer.sublist(_audioBuffer.length - windowSamples);

        if (_audioBuffer.length > windowSamples * 3) {
          _audioBuffer. removeRange(0, _audioBuffer.length - (windowSamples * 2));
        }

        await _runInference(audioWindow);
      }
    } catch (e) {
      print('Error processing recording: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _runInference(List<int> audioData) async {
    if (_tfliteHelper == null) return;

    try {
      final startTime = DateTime.now();

      final features = extractFeatures(audioData);
      print('Extracted ${features.length} features');

      final predictions = await _tfliteHelper! .runInference(features);

      final inferenceTime = DateTime.now().difference(startTime).inMilliseconds. toDouble();

      double maxConfidence = predictions[0];
      int maxIndex = 0;

      for (int i = 1; i < predictions.length; i++) {
        if (predictions[i] > maxConfidence) {
          maxConfidence = predictions[i];
          maxIndex = i;
        }
      }

      final bestLabel = labels[maxIndex];

      // Get noise and unknown confidence for comparison
      final noiseIdx = labels.indexOf("noise");
      final unknownIdx = labels.indexOf("unknown");
      final noiseConf = predictions[noiseIdx];
      final unknownConf = predictions[unknownIdx];

      // More lenient detection:
      // 1.  Confidence >= threshold (0.35)
      // 2. Not noise or unknown
      // 3. Command confidence > noise confidence (command harus lebih tinggi dari noise)
      final isValidCommand = maxConfidence >= confThreshold &&
          bestLabel.toLowerCase() != "noise" &&
          bestLabel. toLowerCase() != "unknown" &&
          maxConfidence > noiseConf;

      final command = isValidCommand ? bestLabel : "N/A";

      if (isValidCommand) {
        print('=== COMMAND DETECTED: $bestLabel (${(maxConfidence * 100).toStringAsFixed(1)}%) ===');
      }

      final indexed = <MapEntry<int, double>>[];
      for (int i = 0; i < predictions. length; i++) {
        indexed.add(MapEntry(i, predictions[i]));
      }
      indexed.sort((a, b) => b.value.compareTo(a. value));

      final topPredictions = indexed
          .take(3) // Show top 3 instead of 2
          .map((e) => PredictionResult(labels[e.key], e.value))
          .toList();

      print('Top: ${topPredictions.map((p) => '${p.label}:${(p.confidence * 100).toStringAsFixed(1)}%'). join(", ")} | Inference: ${inferenceTime.toStringAsFixed(1)}ms');

      onPrediction(command, topPredictions, inferenceTime);
    } catch (e) {
      print('Inference error: $e');
    }
  }

  Future<void> stopListening() async {
    _inferenceTimer?.cancel();
    _inferenceTimer = null;

    await _recorder?.stopRecorder();

    if (_recordingPath != null) {
      try {
        final file = File(_recordingPath! );
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('Error deleting recording file: $e');
      }
      _recordingPath = null;
    }

    _audioBuffer.clear();
    _lastFileSize = 0;
    _isProcessing = false;
    print('Recording stopped');
  }

  void dispose() {
    stopListening();
    _recorder?.closeRecorder();
    _tfliteHelper?.dispose();
  }
}