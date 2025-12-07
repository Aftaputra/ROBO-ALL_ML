package com.example.robodu_cvml

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity: FlutterActivity() {
    private val CV_CHANNEL = "cv_training/model"
    private val AUDIO_CHANNEL = "audio_keyword/model"
    
    private var cvHelper: TransferLearningHelper? = null
    private var audioHelper: AudioKeywordHelper? = null
    private var trainingJob: Job? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // ==========================================
        // CV CHANNEL (EXISTING - WORKING)
        // ==========================================
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CV_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initModel" -> {
                    try {
                        cvHelper = TransferLearningHelper(context, 2)
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
                            cvHelper?.addSample(imageData, className)
                            result.success(cvHelper?.getSampleCount() ?: 0)
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
                                val trainingResult = cvHelper?.startTraining(epochs)
                                
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
                            val output = cvHelper?.classify(imageData)
                            result.success(output?.toList())
                        } else {
                            result.error("INVALID_ARGS", "Missing data", null)
                        }
                    } catch (e: Exception) {
                        result.error("CLASSIFY_ERROR", e.message, null)
                    }
                }
                
                "resetModel" -> {
                    try {
                        cvHelper?.resetModel(2)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RESET_ERROR", e.message, null)
                    }
                }
                
                "getSamplesInfo" -> {
                    try {
                        val samplesPerClass = cvHelper?.getSamplesPerClass()
                        result.success(mapOf(
                            "total" to (cvHelper?.getSampleCount() ?: 0),
                            "perClass" to samplesPerClass
                        ))
                    } catch (e: Exception) {
                        result.error("INFO_ERROR", e.message, null)
                    }
                }
                
                else -> result.notImplemented()
            }
        }
        
        // ==========================================
        // AUDIO CHANNEL (NEW)
        // ==========================================
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initModel" -> {
                    try {
                        audioHelper = AudioKeywordHelper(context) { keyword, confidence, inferenceTime ->
                            CoroutineScope(Dispatchers.Main).launch {
                                MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
                                    .invokeMethod("onKeywordDetected", mapOf(
                                        "keyword" to keyword,
                                        "confidence" to confidence.toDouble(),
                                        "inferenceTime" to inferenceTime.toDouble()
                                    ))
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
                
                "startListening" -> {
                    try {
                        audioHelper?.startListening()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("START_ERROR", e.message, null)
                    }
                }
                
                "stopListening" -> {
                    try {
                        audioHelper?.stopListening()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_ERROR", e.message, null)
                    }
                }
                
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        trainingJob?.cancel()
        cvHelper?.close()
        audioHelper?.close()
        super.onDestroy()
    }
}