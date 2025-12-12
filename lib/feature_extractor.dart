import 'dart:math' as math;
import 'package:scidart/numdart.dart';
import 'package:scidart/scidart.dart';

double frequencyToMel(double f) => 1127.0 * math.log(1 + f / 700.0);
double melToFrequency(double mel) => 700.0 * (math.exp(mel / 1127.0) - 1);
List<double> zeroHandling(List<double> x) => x.map((v) => v == 0 ? 1e-10 : v).toList();

List<double> triangle(List<double> x, int left, int middle, int right) {
  return x.map((v) {
    double out = 0.0;
    if (v > left && v <= middle) {
      out = (v - left) / (middle - left);
    } else if (v >= middle && v < right) {
      out = (right - v) / (right - middle);
    }
    return out;
  }).toList();
}

List<double> linspaceD(double start, double end, int num) {
  if (num == 1) return [start];
  var step = (end - start) / (num - 1);
  return List<double>.generate(num, (i) => start + step * i);
}

Map<String, dynamic> filterbanks(int numFilter, int coefficients, double samplingFreq,
    {double? lowFreq, double?  highFreq}) {
  highFreq ??= samplingFreq / 2.0;
  lowFreq ??= 300.0;
  if (highFreq > samplingFreq / 2.0) throw ArgumentError('high_freq too large');
  if (lowFreq < 0) throw ArgumentError('low_freq cannot be less than zero');

  var mels = linspaceD(frequencyToMel(lowFreq), frequencyToMel(highFreq), numFilter + 2);
  var hertz = mels. map(melToFrequency).toList();
  hertz[hertz.length - 1] = hertz. last - 0.001;

  var fftpoints = (coefficients - 1) * 2;
  var freqIndex = hertz.map((h) => ((fftpoints + 1) * h / samplingFreq). floor()).toList();

  var filterbank = List. generate(numFilter, (_) => List<double>.filled(coefficients, 0.0));

  for (var i = 0; i < numFilter; i++) {
    var left = freqIndex[i];
    var middle = freqIndex[i + 1];
    var right = freqIndex[i + 2];
    if (right - left <= 0) continue;
    var z = linspaceD(left. toDouble(), right.toDouble(), right - left + 1);
    var tri = triangle(z, left, middle, right);
    for (var k = 0; k < tri.length; k++) {
      filterbank[i][left + k] = tri[k];
    }
  }

  return {'filterbank': filterbank, 'freqs': hertz. sublist(1, hertz.length - 1)};
}

double ceilUnlessVeryCloseToFloor(double v) {
  var fl = v.floorToDouble();
  if ((v > fl) && (v - fl < 0.001)) return fl;
  return v.ceilToDouble();
}

Map<String, dynamic> stackFrames(List<double> sig, double samplingFrequency,
    {double frameLength = 0.020, double frameStride = 0.020, bool zeroPadding = true}) {
  var lengthSignal = sig.length;
  var frameSampleLength = ceilUnlessVeryCloseToFloor(samplingFrequency * frameLength). toInt();
  var frameStrideSamples = ceilUnlessVeryCloseToFloor(samplingFrequency * frameStride).toInt();

  int numFrames;
  if (zeroPadding) {
    numFrames = ((lengthSignal - frameSampleLength) / frameStrideSamples).ceil();
  } else {
    var x = (lengthSignal - (frameSampleLength - frameStrideSamples));
    numFrames = (x / frameStrideSamples).floor();
  }

  if (numFrames <= 0) numFrames = 0;

  List<double> signal;
  if (zeroPadding) {
    int lenSig = (numFrames * frameStrideSamples + frameSampleLength). toInt();
    var additive = List<double>.filled(lenSig - lengthSignal, 0.0);
    signal = List<double>.from(sig)..addAll(additive);
  } else {
    int lenSig = ((numFrames - 1) * frameStrideSamples + frameSampleLength). toInt();
    signal = sig.sublist(0, lenSig);
  }

  var frames = List<List<double>>.generate(numFrames, (_) => List<double>.filled(frameSampleLength, 0.0));
  for (var i = 0; i < numFrames; i++) {
    var start = i * frameStrideSamples;
    frames[i] = signal.sublist(start, start + frameSampleLength);
  }

  return {
    'frames': frames,
    'numframes': numFrames,
    'frame_length': frameSampleLength,
    'frame_stride': frameStrideSamples
  };
}

List<List<double>> powerSpectrum(List<List<double>> frames, int fftPoints) {
  var powerSpec = <List<double>>[];
  for (var frame in frames) {
    var arr = Array(frame);
    var specComplex = rfft(arr, n: fftPoints);
    var magArr = arrayComplexAbs(specComplex);
    var magList = magArr.toList();
    var pow = List<double>.filled(magList.length, 0.0);
    for (var i = 0; i < magList.length; i++) {
      pow[i] = (1.0 / fftPoints) * (magList[i] * magList[i]);
    }
    powerSpec.add(pow);
  }
  return powerSpec;
}

List<List<double>> dot(List<List<double>> a, List<List<double>> bT) {
  var m = a.length;
  var n = bT.length;
  var p = bT[0].length;
  var out = List. generate(m, (_) => List<double>.filled(n, 0.0));
  for (var i = 0; i < m; i++) {
    for (var j = 0; j < n; j++) {
      double s = 0.0;
      for (var k = 0; k < p; k++) {
        s += a[i][k] * bT[j][k];
      }
      out[i][j] = s;
    }
  }
  return out;
}

Map<String, dynamic> mfe(List<double> signal,
    {double samplingFrequency = 16000,
    double frameLength = 0.020,
    double frameStride = 0.01,
    int numFilters = 40,
    int fftLength = 512,
    double lowFrequency = 0.0,
    double?  highFrequency}) {
  highFrequency??= samplingFrequency / 2.0;

  var stacked = stackFrames(signal, samplingFrequency,
      frameLength: frameLength, frameStride: frameStride, zeroPadding: false);
  var frames = stacked['frames'] as List<List<double>>;

  var powerSpec = powerSpectrum(frames, fftLength);
  var coefficients = powerSpec[0]. length;

  var frameEnergies = powerSpec.map((row) => row.reduce((a, b) => a + b)). toList();
  frameEnergies = zeroHandling(frameEnergies);

  var fb = filterbanks(numFilters, coefficients, samplingFrequency,
      lowFreq: lowFrequency, highFreq: highFrequency);
  var filterBanks = fb['filterbank'] as List<List<double>>;

  var features = dot(powerSpec, filterBanks);
  for (var i = 0; i < features.length; i++) {
    for (var j = 0; j < features[0].length; j++) {
      if (features[i][j] == 0.0) features[i][j] = 1e-10;
    }
  }

  return {
    'features': features,
    'frame_energies': frameEnergies,
    'filter_freqs': fb['freqs'],
    'filter_banks': filterBanks
  };
}

List<double> preemphasis(List<double> signal, {int shift = 1, double cof = 0.98}) {
  if (shift <= 0) throw ArgumentError('Shift must be positive');
  var rolled = List<double>.from(signal);
  for (var i = 0; i < signal.length; i++) {
    var prev = (i - shift) >= 0 ? signal[i - shift] : signal[signal.length + (i - shift)];
    rolled[i] = prev;
  }
  var out = List<double>.filled(signal.length, 0.0);
  for (var i = 0; i < signal.length; i++) {
    out[i] = signal[i] - cof * rolled[i];
  }
  return out;
}

List<double> extractFeatures(List<num> rawSignal) {
  var sigDurationSec = 1.0;
  var samplingFreq = 16000.0;
  var frameLength = 0.02;
  var frameStride = 0.01;
  var numFilters = 40;
  var fftLength = 256;
  var lowFrequency = 0.0;
  var noiseFloorDb = -100.0;

  var expectedSignalLen = (sigDurationSec * samplingFreq). toInt();
  var signal = rawSignal.map((v) => v.toDouble()).toList();
  if (signal.length < expectedSignalLen) {
    signal = List<double>.from(signal)..addAll(List<double>.filled(expectedSignalLen - signal.length, 0.0));
  } else if (signal. length > expectedSignalLen) {
    signal = signal.sublist(0, expectedSignalLen);
  }

  signal = signal.map((v) => v / math.pow(2, 15)).toList();
  signal = preemphasis(signal);

  var mfeRes = mfe(signal,
      samplingFrequency: samplingFreq,
      frameLength: frameLength,
      frameStride: frameStride,
      numFilters: numFilters,
      fftLength: fftLength,
      lowFrequency: lowFrequency);
  var feats = mfeRes['features'] as List<List<double>>;

  var flat = <double>[];
  for (var r in feats) {
    for (var v in r) flat.add(v);
  }
  for (var i = 0; i < flat.length; i++) {
    var v = flat[i];
    v = math.max(v, 1e-30);
    v = 10 * math.log(v) / math.ln10;
    v = (v - noiseFloorDb) / ((-1 * noiseFloorDb) + 12);
    v = v.clamp(0.0, 1.0);
    v = (v * math.pow(2, 8)). roundToDouble();
    v = v. clamp(0.0, 255.0);
    v = v / math.pow(2, 8);
    flat[i] = v;
  }

  return flat;
}