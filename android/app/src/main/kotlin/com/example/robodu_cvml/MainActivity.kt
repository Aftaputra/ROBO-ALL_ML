package com.example.cv_training_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "cv_training/model"
    private var helper: TransferLearningHelper? = null
    private var trainingJob: Job? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initModel" -> {
                    try {
                        helper = TransferLearningHelper(context, 2)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
                
                "addSample" -> {
                    try {
                        val imageData = call.argument<List<Double>>("imageData")?.map { it.toFloat() }?.toFloatArray()
                        val className = call.argument<String>("className")
                        
                        if (imageData != null && className != null) {
                            helper?.addSample(imageData, className)
                            result.success(helper?.getSampleCount() ?: 0)
                        } else {
                            result.error("INVALID_ARGS", "Missing data", null)
                        }
                    } catch (e: Exception) {
                        result.error("ADD_SAMPLE_ERROR", e.message, null)
                    }
                }
                
                "train" -> {
                    try {
                        val epochs = call.argument<Int>("epochs") ?: 10
                        
                        trainingJob = CoroutineScope(Dispatchers.IO).launch {
                            try {
                                val trainingResult = helper?.startTraining(epochs)
                                
                                withContext(Dispatchers.Main) {
                                    if (trainingResult != null && trainingResult.loss >= 0) {
                                        result.success(mapOf(
                                            "loss" to trainingResult.loss.toDouble(),
                                            "epochs" to epochs,
                                            "message" to trainingResult.message,
                                            "samplesPerClass" to trainingResult.samplesPerClass
                                        ))
                                    } else {
                                        result.error("TRAIN_ERROR", trainingResult?.message ?: "Unknown error", null)
                                    }
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("TRAIN_ERROR", e.message, null)
                                }
                            }
                        }
                    } catch (e: Exception) {
                        result.error("TRAIN_ERROR", e.message, null)
                    }
                }
                
                "classify" -> {
                    try {
                        val imageData = call.argument<List<Double>>("imageData")?.map { it.toFloat() }?.toFloatArray()
                        
                        if (imageData != null) {
                            val output = helper?.classify(imageData)
                            result.success(output?.toList())
                        } else {
                            result.error("INVALID_ARGS", "Missing data", null)
                        }
                    } catch (e: Exception) {
                        result.error("CLASSIFY_ERROR", e.message, null)
                    }
                }
                
                // NEW: Reset model
                "resetModel" -> {
                    try {
                        helper?.resetModel(2)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RESET_ERROR", e.message, null)
                    }
                }
                
                // NEW: Get samples info
                "getSamplesInfo" -> {
                    try {
                        val samplesPerClass = helper?.getSamplesPerClass()
                        result.success(mapOf(
                            "total" to (helper?.getSampleCount() ?: 0),
                            "perClass" to samplesPerClass
                        ))
                    } catch (e: Exception) {
                        result.error("INFO_ERROR", e.message, null)
                    }
                }
                
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        trainingJob?.cancel()
        helper?.close()
        super.onDestroy()
    }
}