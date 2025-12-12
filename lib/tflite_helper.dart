import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class TFLiteHelper {
  static const platform = MethodChannel('com.robodu.tflite');

  Future<void> loadModel(String assetPath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/model.tflite';
      final modelFile = File(modelPath);

      if (!await modelFile.exists()) {
        print('Copying model from assets...');
        final modelData = await rootBundle. load(assetPath);
        final buffer = modelData.buffer;
        await modelFile.writeAsBytes(
            buffer.asUint8List(modelData.offsetInBytes, modelData.lengthInBytes));
      }

      final result = await platform.invokeMethod('loadModel', {
        'modelPath': modelPath,
      });

      print('Model loaded: $result');
    } catch (e) {
      print('Error loading model: $e');
      rethrow;
    }
  }

  Future<List<double>> runInference(List<double> inputFeatures) async {
    try {
      final result = await platform.invokeMethod('runInference', {
        'input': inputFeatures,
      });

      return (result as List). map((e) => (e as num).toDouble()).toList();
    } catch (e) {
      print('Inference error: $e');
      rethrow;
    }
  }

  void dispose() {
    try {
      platform. invokeMethod('closeModel');
    } catch (e) {
      print('Error closing model: $e');
    }
  }
}