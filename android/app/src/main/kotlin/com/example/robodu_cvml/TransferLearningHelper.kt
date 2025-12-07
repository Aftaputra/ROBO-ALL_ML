package com.example.robodu_cvml

import android.content.Context
import android.util.Log
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.common.FileUtil
import java.nio.FloatBuffer

class TransferLearningHelper(
    private val context: Context,
    numThreads: Int = 2
) {
    private var interpreter: Interpreter? = null
    private val trainingSamples: MutableList<TrainingSample> = mutableListOf()

    init {
        initializeModel(numThreads)
    }

    private fun initializeModel(numThreads: Int) {
        val options = Interpreter.Options()
        options.numThreads = numThreads
        val modelFile = FileUtil.loadMappedFile(context, "flutter_assets/assets/model.tflite")
        interpreter = Interpreter(modelFile, options)
        
        Log.d(TAG, "✅ Model initialized")
    }

    fun addSample(imageData: FloatArray, className: String) {
        try {
            val reshaped = reshapeInput(imageData)
            val bottleneck = loadBottleneck(reshaped)
            
            val avgBottleneck = bottleneck.average()
            Log.d(TAG, "Bottleneck - avg: $avgBottleneck, class: $className")
            
            val label = encoding(getClassIndex(className))
            trainingSamples.add(TrainingSample(bottleneck, label, className))
            
            Log.d(TAG, "Sample added for class $className. Total: ${trainingSamples.size}")
        } catch (e: Exception) {
            Log.e(TAG, "Error adding sample: ${e.message}", e)
            throw e
        }
    }

    fun getSampleCount(): Int = trainingSamples.size
    
    // NEW: Get samples per class
    fun getSamplesPerClass(): Map<String, Int> {
        return trainingSamples.groupBy { it.className }.mapValues { it.value.size }
    }

    // NEW: Clear all samples and reset model
    fun resetModel(numThreads: Int = 2) {
        Log.d(TAG, "🔄 Resetting model...")
        
        // Clear samples
        trainingSamples.clear()
        
        // Close old interpreter
        interpreter?.close()
        
        // Reinitialize model (fresh weights)
        initializeModel(numThreads)
        
        Log.d(TAG, "✅ Model reset complete")
    }

    fun startTraining(numEpochs: Int = 10): TrainingResult {
        if (trainingSamples.isEmpty()) {
            Log.w(TAG, "No training samples!")
            return TrainingResult(-1f, "No samples", null)
        }
        
        // Check class balance
        val samplesPerClass = getSamplesPerClass()
        Log.d(TAG, "Samples per class: $samplesPerClass")
        
        if (samplesPerClass.size < 2) {
            return TrainingResult(-1f, "Need at least 2 different classes", samplesPerClass)
        }
        
        // Warn if imbalanced
        val minSamples = samplesPerClass.values.minOrNull() ?: 0
        val maxSamples = samplesPerClass.values.maxOrNull() ?: 0
        if (maxSamples > minSamples * 3) {
            Log.w(TAG, "⚠️ Class imbalance detected! Min: $minSamples, Max: $maxSamples")
        }
        
        Log.d(TAG, "Starting training with ${trainingSamples.size} samples, $numEpochs epochs")
        
        var totalLoss = 0f
        var batchCount = 0
        
        repeat(numEpochs) { epoch ->
            trainingSamples.shuffle()
            
            val batchSize = getTrainBatchSize()
            
            trainingBatches(batchSize).forEach { batch ->
                val bottlenecks = batch.map { it.bottleneck }.toTypedArray()
                val labels = batch.map { it.label }.toTypedArray()
                
                val loss = training(bottlenecks, labels)
                totalLoss += loss
                batchCount++
                
                if (epoch == 0 || epoch == numEpochs - 1) {
                    Log.d(TAG, "  Epoch ${epoch + 1}, batch loss: $loss")
                }
            }
        }
        
        val avgLoss = if (batchCount > 0) totalLoss / batchCount else 0f
        Log.d(TAG, "Training complete! Avg loss: $avgLoss")
        
        return TrainingResult(avgLoss, "Success", samplesPerClass)
    }

    fun classify(imageData: FloatArray): FloatArray {
        try {
            val reshaped = reshapeInput(imageData)
            
            val inputs = hashMapOf<String, Any>("feature" to reshaped)
            val output = Array(1) { FloatArray(5) }
            val outputs = hashMapOf<String, Any>("output" to output)
            
            interpreter?.runSignature(inputs, outputs, "infer")
            
            val result = output[0]
            
            // Log top prediction
            val maxIdx = result.indices.maxByOrNull { result[it] } ?: 0
            Log.d(TAG, "Inference: Class ${maxIdx + 1} = ${result[maxIdx] * 100}%")
            
            return result
        } catch (e: Exception) {
            Log.e(TAG, "Classify error: ${e.message}", e)
            throw e
        }
    }

    private fun reshapeInput(flatArray: FloatArray): Array<Array<Array<FloatArray>>> {
        val batch = 1
        val height = 224
        val width = 224
        val channels = 3
        
        if (flatArray.size != height * width * channels) {
            Log.e(TAG, "Invalid input size: ${flatArray.size}, expected: ${height * width * channels}")
            throw IllegalArgumentException("Invalid input size")
        }
        
        val reshaped = Array(batch) {
            Array(height) {
                Array(width) {
                    FloatArray(channels)
                }
            }
        }
        
        var idx = 0
        for (h in 0 until height) {
            for (w in 0 until width) {
                for (c in 0 until channels) {
                    reshaped[0][h][w][c] = flatArray[idx++]
                }
            }
        }
        
        return reshaped
    }

    private fun loadBottleneck(imageData: Array<Array<Array<FloatArray>>>): FloatArray {
        val inputs = hashMapOf<String, Any>("feature" to imageData)
        val bottleneck = Array(1) { FloatArray(62720) }
        val outputs = hashMapOf<String, Any>("bottleneck" to bottleneck)
        
        interpreter?.runSignature(inputs, outputs, "load")
        return bottleneck[0]
    }

    private fun training(bottlenecks: Array<FloatArray>, labels: Array<FloatArray>): Float {
        val inputs = hashMapOf<String, Any>(
            "bottleneck" to bottlenecks,
            "label" to labels
        )
        val loss = FloatBuffer.allocate(1)
        val outputs = hashMapOf<String, Any>("loss" to loss)
        
        interpreter?.runSignature(inputs, outputs, "train")
        return loss.get(0)
    }

    private fun encoding(classId: Int): FloatArray {
        val encoded = FloatArray(5)
        encoded[classId] = 1.0f
        return encoded
    }

    private fun getClassIndex(className: String): Int {
        return when (className) {
            "1" -> 0
            "2" -> 1
            "3" -> 2
            "4" -> 3
            "5" -> 4
            else -> 0
        }
    }

    private fun getTrainBatchSize(): Int {
        return minOf(maxOf(1, trainingSamples.size), EXPECTED_BATCH_SIZE)
    }

    private fun trainingBatches(trainBatchSize: Int): Sequence<List<TrainingSample>> = sequence {
        var nextIndex = 0
        
        while (nextIndex < trainingSamples.size) {
            val toIndex = nextIndex + trainBatchSize
            
            if (toIndex >= trainingSamples.size) {
                yield(trainingSamples.subList(
                    trainingSamples.size - trainBatchSize,
                    trainingSamples.size
                ))
                break
            } else {
                yield(trainingSamples.subList(nextIndex, toIndex))
            }
            
            nextIndex = toIndex
        }
    }

    fun close() {
        interpreter?.close()
    }

    data class TrainingSample(
        val bottleneck: FloatArray, 
        val label: FloatArray,
        val className: String // NEW: track class name
    )
    
    data class TrainingResult(
        val loss: Float,
        val message: String,
        val samplesPerClass: Map<String, Int>?
    )

    companion object {
        private const val TAG = "TransferLearningHelper"
        private const val EXPECTED_BATCH_SIZE = 20
    }
}