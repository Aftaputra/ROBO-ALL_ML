package com.example.robodu_cvml

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.common.FileUtil
import kotlinx.coroutines.*
import kotlin.math.*

class AudioKeywordHelper(
    private val context: Context,
    private val onKeywordDetected: (String, Float, Float) -> Unit
) {
    private var interpreter: Interpreter? = null
    private var audioRecord: AudioRecord? = null
    private var recordingJob: Job? = null
    
    // OPTIMIZED Constants
    private val sampleRate = 16000
    private val chunkDuration = 0.01      // 10ms
    private val inferInterval = 0.2       // 200ms (FASTER - dari 500ms)
    private val windowDuration = 0.5      // 0.5 sec (SHORTER - dari 1.0 sec)
    private val confThreshold = 0.6f      // RAISED (dari 0.3)
    private val noiseThreshold = 0.01f    // NEW: minimum audio energy
    
    // Labels - EXACTLY from Python
    private val labels = listOf("robodu", "perkenalan", "kanan", "kiri", "maju", "mundur")
    
    // Audio buffer
    private val windowSamples = (sampleRate * windowDuration).toInt()
    private val audioBuffer = mutableListOf<Float>()
    private var lastInferTime = 0L
    private var lastDetectedKeyword = ""
    private var lastDetectedTime = 0L
    
    companion object {
        private const val TAG = "AudioKeywordHelper"
    }
    
    init {
        loadModel()
    }
    
    private fun loadModel() {
        try {
            val options = Interpreter.Options()
            options.numThreads = 4  // INCREASED from 2
            val modelFile = FileUtil.loadMappedFile(context, "flutter_assets/assets/robodu.tflite")
            interpreter = Interpreter(modelFile, options)
            
            val inputShape = interpreter!!.getInputTensor(0).shape()
            val outputShape = interpreter!!.getOutputTensor(0).shape()
            
            Log.d(TAG, "✅ Audio model loaded")
            Log.d(TAG, "Input shape: ${inputShape.contentToString()}")
            Log.d(TAG, "Output shape: ${outputShape.contentToString()}")
            Log.d(TAG, "Window: ${windowDuration}s, Interval: ${inferInterval}s")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Model load error: ${e.message}", e)
            throw e
        }
    }
    
    fun startListening() {
        if (recordingJob?.isActive == true) {
            Log.w(TAG, "Already listening")
            return
        }
        
        try {
            val chunkSize = (sampleRate * chunkDuration).toInt()
            val bufferSize = maxOf(
                AudioRecord.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                ),
                chunkSize * 2
            )
            
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,  // CHANGED from MIC (better for speech)
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )
            
            audioRecord?.startRecording()
            lastInferTime = System.currentTimeMillis()
            audioBuffer.clear()
            
            recordingJob = CoroutineScope(Dispatchers.IO).launch {
                processAudio(chunkSize)
            }
            
            Log.d(TAG, "🎧 Started listening")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Start listening error: ${e.message}", e)
        }
    }
    
    private suspend fun processAudio(chunkSize: Int) {
        val buffer = ShortArray(chunkSize)
        
        while (recordingJob?.isActive == true) {
            val readSize = audioRecord?.read(buffer, 0, chunkSize) ?: 0
            
            if (readSize > 0) {
                // Convert to float32 [-1, 1]
                val floatSamples = buffer.take(readSize).map { it / 32768f }
                audioBuffer.addAll(floatSamples)
                
                // Keep only last windowSamples
                if (audioBuffer.size > windowSamples) {
                    audioBuffer.subList(0, audioBuffer.size - windowSamples).clear()
                }
                
                // Check inference timing
                val currentTime = System.currentTimeMillis()
                if ((currentTime - lastInferTime) >= (inferInterval * 1000) && 
                    audioBuffer.size >= windowSamples) {
                    
                    lastInferTime = currentTime
                    val audio = audioBuffer.takeLast(windowSamples).toFloatArray()
                    
                    // NEW: Check if audio has enough energy (not just silence/noise)
                    if (hasSignificantEnergy(audio)) {
                        runInference(audio)
                    }
                }
            }
            
            delay(5)  // REDUCED from 10ms
        }
    }
    
    // NEW: Check if audio has enough energy
    private fun hasSignificantEnergy(audio: FloatArray): Boolean {
        val rms = sqrt(audio.map { it * it }.average().toFloat())
        return rms > noiseThreshold
    }
    
private fun runInference(audio: FloatArray) {
    try {
        val startTime = System.nanoTime()
        
        // Preprocess: Normalize audio
        val normalizedAudio = normalizeAudio(audio)
        
        // Extract MFCC features [13, 100]
        val mfcc = extractFeatures(normalizedAudio)
        
        // Model input [1, 13, 100, 1]
        val inputBuffer = Array(1) {
            Array(13) { i ->
                Array(100) { j ->
                    FloatArray(1) {
                        mfcc[i][j]
                    }
                }
            }
        }
        
        val outputBuffer = Array(1) { FloatArray(6) }
        
        interpreter?.allocateTensors()
        interpreter?.run(inputBuffer, outputBuffer)
        
        val inferenceTime = (System.nanoTime() - startTime) / 1_000_000f
        
        val probs = outputBuffer[0]
        val maxIdx = probs.indices.maxByOrNull { probs[it] } ?: 0
        val confidence = probs[maxIdx]
        
        // Log top 3 predictions
        val topIndices = probs.indices.sortedByDescending { probs[it] }.take(3)
        val topPreds = topIndices.joinToString { "${labels[it]}:${String.format("%.2f", probs[it])}" }
        
        // FIX: Use String.format or toInt() instead of toStringAsFixed
        Log.d(TAG, "Top3: $topPreds | ${inferenceTime.toInt()}ms")
        
        // Check confidence threshold
        if (confidence > confThreshold) {
            val keyword = labels[maxIdx]
            val currentTime = System.currentTimeMillis()
            
            // Prevent duplicate detection (debounce 1 second)
            if (keyword != lastDetectedKeyword || (currentTime - lastDetectedTime) > 1000) {
                lastDetectedKeyword = keyword
                lastDetectedTime = currentTime
                
                Log.d(TAG, "🎯 DETECTED: $keyword (${String.format("%.2f", confidence)})")
                onKeywordDetected(keyword, confidence, inferenceTime)
            }
        }
        
    } catch (e: Exception) {
        Log.e(TAG, "❌ Inference error: ${e.message}", e)
    }
}
    
    // NEW: Normalize audio to reduce volume variance
    private fun normalizeAudio(audio: FloatArray): FloatArray {
        val max = audio.maxOrNull()?.absoluteValue ?: 1f
        return if (max > 0.01f) {
            audio.map { it / max }.toFloatArray()
        } else {
            audio
        }
    }
    
    private fun extractFeatures(audio: FloatArray): Array<FloatArray> {
        val nMfcc = 13
        val maxPadLen = 100
        return computeMFCC(audio, nMfcc, maxPadLen)
    }
    
    private fun computeMFCC(audio: FloatArray, nMfcc: Int, maxPadLen: Int): Array<FloatArray> {
        val frameSize = 512
        val hopSize = maxOf(1, audio.size / maxPadLen)
        
        val mfcc = Array(nMfcc) { FloatArray(maxPadLen) }
        
        var frameIndex = 0
        var pos = 0
        
        while (pos + frameSize <= audio.size && frameIndex < maxPadLen) {
            val frame = audio.sliceArray(pos until pos + frameSize)
            val windowed = applyHammingWindow(frame)
            val spectrum = computePowerSpectrum(windowed)
            
            for (i in 0 until nMfcc) {
                mfcc[i][frameIndex] = computeMelCoefficient(spectrum, i)
            }
            
            pos += hopSize
            frameIndex++
        }
        
        // Pad if needed
        if (frameIndex < maxPadLen) {
            for (i in 0 until nMfcc) {
                for (j in frameIndex until maxPadLen) {
                    mfcc[i][j] = 0f
                }
            }
        }
        
        return mfcc
    }
    
    private fun applyHammingWindow(frame: FloatArray): FloatArray {
        val n = frame.size
        return FloatArray(n) { i ->
            val window = 0.54f - 0.46f * cos(2 * PI.toFloat() * i / (n - 1))
            frame[i] * window
        }
    }
    
    private fun computePowerSpectrum(frame: FloatArray): FloatArray {
        val n = frame.size
        val spectrum = FloatArray(n / 2)
        
        for (k in 0 until n / 2) {
            var real = 0f
            var imag = 0f
            for (t in 0 until n) {
                val angle = 2 * PI.toFloat() * k * t / n
                real += frame[t] * cos(angle)
                imag -= frame[t] * sin(angle)
            }
            spectrum[k] = sqrt(real * real + imag * imag)
        }
        
        return spectrum
    }
    
    private fun computeMelCoefficient(spectrum: FloatArray, index: Int): Float {
        val melBin = (index * spectrum.size / 26).coerceIn(0, spectrum.size - 1)
        return ln(spectrum[melBin] + 1e-10f)
    }
    
    fun stopListening() {
        try {
            recordingJob?.cancel()
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
            audioBuffer.clear()
            
            Log.d(TAG, "⏸️ Stopped listening")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Stop error: ${e.message}", e)
        }
    }
    
    fun close() {
        stopListening()
        interpreter?.close()
    }
}