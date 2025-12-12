package com.example.robodu_cvml

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.tensorflow.lite. Interpreter
import java.io.File
import java.nio.ByteBuffer
import java.nio. ByteOrder

class MainActivity:  FlutterActivity() {
    private val CV_CHANNEL = "cv_training/model"
    private val AUDIO_CHANNEL = "com.robodu.tflite"
    
    private var cvHelper: TransferLearningHelper? = null
    private var audioInterpreter:  Interpreter? = null
    private var trainingJob: Job? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // CV CHANNEL
        MethodChannel(flutterEngine.dartExecutor. binaryMessenger, CV_CHANNEL).setMethodCallHandler { call, result ->
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
                        val imageData = call.argument<List<Double>>("imageData")?.map { it.toFloat() }?. toFloatArray()
                        val className = call.argument<String>("className")
                        
                        if (imageData != null && className != null) {
                            cvHelper?.addSample(imageData, className)
                            result. success(cvHelper?.getSampleCount() ?: 0)
                        } else {
                            result.error("INVALID_ARGS", "Missing data", null)
                        }
                    } catch (e: Exception) {
                        result.error("ADD_SAMPLE_ERROR", e. message, null)
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
                                            "loss" to trainingResult.loss. toDouble(),
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
                                    result.error("TRAIN_ERROR", e. message, null)
                                }
                            }
                        }
                    } catch (e:  Exception) {
                        result.error("TRAIN_ERROR", e.message, null)
                    }
                }
                
                "classify" -> {
                    try {
                        val imageData = call.argument<List<Double>>("imageData")?.map { it.toFloat() }?.toFloatArray()
                        
                        if (imageData != null) {
                            val output = cvHelper?.classify(imageData)
                            result.success(output?. toList())
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
        
        // AUDIO CHANNEL
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            when (call. method) {
                "loadModel" -> {
                    val modelPath = call.argument<String>("modelPath")
                    if (modelPath != null) {
                        try {
                            val modelFile = File(modelPath)
                            audioInterpreter = Interpreter(modelFile)
                            result.success("Model loaded successfully")
                        } catch (e: Exception) {
                            result.error("LOAD_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Model path is null", null)
                    }
                }
                
                "runInference" -> {
                    val input = call.argument<List<Double>>("input")
                    if (input != null && audioInterpreter != null) {
                        try {
                            val inputArray = input.map { it.toFloat() }.toFloatArray()
                            val inputBuffer = ByteBuffer.allocateDirect(inputArray.size * 4)
                            inputBuffer.order(ByteOrder. nativeOrder())
                            inputBuffer.asFloatBuffer().put(inputArray)

                            val outputBuffer = ByteBuffer.allocateDirect(8 * 4)
                            outputBuffer.order(ByteOrder.nativeOrder())

                            audioInterpreter?.run(inputBuffer, outputBuffer)

                            outputBuffer.rewind()
                            val output = FloatArray(8)
                            outputBuffer.asFloatBuffer().get(output)

                            result.success(output. map { it.toDouble() })
                        } catch (e:  Exception) {
                            result. error("INFERENCE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_STATE", "Input is null or model not loaded", null)
                    }
                }
                
                "closeModel" -> {
                    audioInterpreter?.close()
                    audioInterpreter = null
                    result.success(null)
                }
                
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        trainingJob?.cancel()
        cvHelper?.close()
        audioInterpreter?.close()
        super.onDestroy()
    }
}