import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// 27 emotion → 6 DSP parameter profiles.
/// Each tuple: (pitch_shift_semitones, pitch_variance_scale,
///              brightness_db, tension, breathiness, speed_ratio)
const Map<String, List<double>> _emotionProfiles = {
  'admiration': [1.5, 1.3, 2.0, 0.2, 0.10, 1.00],
  'amusement': [3.0, 1.6, 3.0, 0.0, 0.00, 1.08],
  'anger': [2.0, 1.8, 6.0, 0.5, 0.00, 1.10],
  'annoyance': [1.0, 1.3, 3.0, 0.3, 0.00, 1.05],
  'approval': [0.5, 1.1, 1.5, 0.1, 0.00, 1.00],
  'caring': [-1.0, 0.8, -1.0, 0.1, 0.20, 0.95],
  'confusion': [0.0, 1.2, 0.0, 0.1, 0.08, 0.98],
  'curiosity': [2.0, 1.4, 1.0, 0.0, 0.00, 1.03],
  'desire': [-1.5, 0.7, -2.0, 0.2, 0.30, 0.90],
  'disappointment': [-2.0, 0.6, -3.0, 0.1, 0.20, 0.92],
  'disgust': [-0.5, 0.9, 0.0, 0.3, 0.05, 0.95],
  'embarrassment': [-2.0, 0.7, -1.0, 0.0, 0.20, 0.93],
  'excitement': [4.0, 1.8, 5.0, 0.0, 0.00, 1.12],
  'fear': [3.0, 1.5, 1.0, 0.2, 0.20, 1.06],
  'gratitude': [1.0, 1.1, 1.0, 0.1, 0.10, 0.98],
  'grief': [-4.0, 0.4, -4.0, 0.0, 0.30, 0.85],
  'joy': [3.0, 1.6, 4.0, 0.0, 0.00, 1.08],
  'love': [-1.5, 0.6, -1.0, 0.2, 0.30, 0.88],
  'nervousness': [2.0, 1.3, 0.0, 0.2, 0.15, 1.04],
  'optimism': [1.5, 1.3, 2.0, 0.0, 0.00, 1.03],
  'pride': [2.0, 1.4, 3.0, 0.1, 0.00, 1.03],
  'realization': [2.5, 1.5, 1.0, 0.0, 0.00, 1.00],
  'relief': [-0.5, 0.9, 0.0, 0.0, 0.15, 0.97],
  'remorse': [-3.0, 0.5, -2.0, 0.1, 0.25, 0.88],
  'sadness': [-4.0, 0.4, -5.0, 0.0, 0.35, 0.82],
  'surprise': [5.0, 1.8, 5.0, 0.2, 0.00, 1.08],
  'neutral': [0.0, 1.0, 0.0, 0.0, 0.00, 1.00],
};

/// In-process emotional voice DSP.
///
/// Reads a WAV file, applies STFT-domain emotional audio effects
/// (pitch shift, brightness, tension, breathiness, time-stretch),
/// and writes the result back to a new WAV file.
class EmotionalVoiceDsp {
  static const int _nfft = 1024;
  static const int _hop = 256;
  static final int _bins = _nfft ~/ 2 + 1;
  static const double _peak = 0.95;

  /// Process [inputFile] with the given [emotion] label.
  /// Returns a new [File] with the emotion-adapted audio.
  static Future<File> process(File inputFile, String emotion) async {
    final profile = _emotionProfiles[emotion] ?? _emotionProfiles['neutral']!;
    final (samples, sampleRate, bitsPerSample) = await _readWav(inputFile);
    if (samples.isEmpty) throw Exception('Empty WAV data');

    final processed = _processSamples(samples, sampleRate, profile);

    final outPath =
        '${inputFile.parent.path}/emotional_${p.basenameWithoutExtension(inputFile.path)}_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _writeWav(File(outPath), processed, sampleRate, bitsPerSample);
    return File(outPath);
  }

  // ── WAV I/O ─────────────────────────────────────────────────

  static Future<(Float64List, int, int)> _readWav(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length < 44) throw Exception('File too small for WAV header');

    final bd = ByteData.sublistView(bytes);
    final sampleRate = bd.getUint32(24, Endian.little);
    final channels = bd.getUint16(22, Endian.little);
    final bitsPerSample = bd.getUint16(34, Endian.little);

    int dataOffset = 12;
    Float64List? samples;

    while (dataOffset < bytes.length - 8) {
      final chunkId =
          String.fromCharCodes(bytes.sublist(dataOffset, dataOffset + 4));
      final chunkSize = bd.getUint32(dataOffset + 4, Endian.little);
      if (chunkId == 'data') {
        final pcmStart = dataOffset + 8;
        final pcmEnd = (pcmStart + chunkSize).clamp(0, bytes.length);
        final totalSamples = (pcmEnd - pcmStart) ~/ (bitsPerSample ~/ 8);
        final monoLength = totalSamples ~/ channels;
        samples = Float64List(monoLength);

        if (bitsPerSample == 16) {
          for (int i = 0; i < monoLength; i++) {
            double sum = 0;
            for (int ch = 0; ch < channels; ch++) {
              final idx = pcmStart + (i * channels + ch) * 2;
              sum += bd.getInt16(idx, Endian.little) / 32768.0;
            }
            samples[i] = sum / channels;
          }
        } else if (bitsPerSample == 32) {
          for (int i = 0; i < monoLength; i++) {
            double sum = 0;
            for (int ch = 0; ch < channels; ch++) {
              final idx = pcmStart + (i * channels + ch) * 4;
              sum += bd.getFloat32(idx, Endian.little);
            }
            samples[i] = sum / channels;
          }
        } else {
          throw Exception('Unsupported bitsPerSample: $bitsPerSample');
        }
        break;
      }
      dataOffset += 8 + chunkSize;
    }
    if (samples == null) throw Exception('No data chunk found');
    return (samples, sampleRate, bitsPerSample);
  }

  static Future<void> _writeWav(
    File file,
    Float64List samples,
    int sampleRate,
    int bitsPerSample,
  ) async {
    final byteRate = sampleRate * (bitsPerSample ~/ 8);
    final blockAlign = bitsPerSample ~/ 8;
    final dataSize = samples.length * blockAlign;
    final header = ByteData(44);

    void w8(int off, int v) => header.setUint8(off, v);
    w8(0, 0x52); w8(1, 0x49); w8(2, 0x46); w8(3, 0x46);
    header.setUint32(4, 36 + dataSize, Endian.little);
    w8(8, 0x57); w8(9, 0x41); w8(10, 0x56); w8(11, 0x45);
    w8(12, 0x66); w8(13, 0x6D); w8(14, 0x74); w8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    w8(36, 0x64); w8(37, 0x61); w8(38, 0x74); w8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little);

    final sink = file.openWrite();
    sink.add(header.buffer.asUint8List());

    final pcm = Uint8List(dataSize);
    if (bitsPerSample == 16) {
      for (int i = 0; i < samples.length; i++) {
        final clamped = (samples[i] * 32767.0).clamp(-32768.0, 32767.0).toInt();
        pcm[i * 2] = clamped & 0xFF;
        pcm[i * 2 + 1] = (clamped >> 8) & 0xFF;
      }
    } else {
      final bd2 = ByteData(dataSize);
      for (int i = 0; i < samples.length; i++) {
        bd2.setFloat32(i * 4, samples[i].clamp(-1.0, 1.0), Endian.little);
      }
      pcm.setAll(0, bd2.buffer.asUint8List());
    }
    sink.add(pcm);
    await sink.close();
  }

  // ── Main DSP pipeline ───────────────────────────────────────

  static Float64List _processSamples(
    Float64List samples, int sampleRate, List<double> profile,
  ) {
    final pitchSt = profile[0];
    final pitchVar = profile[1];
    final brightnessDb = profile[2];
    final tension = profile[3];
    final breathiness = profile[4];
    final speedRatio = profile[5];

    final (mag, phase, numFrames) = _stft(samples);

    var m = mag;
    var p = phase;
    var nf = numFrames;

    if (pitchSt.abs() >= 0.5) m = _pitchShift(m, pitchSt);
    if (pitchVar != 1.0) m = _applyPitchVariance(m, pitchVar);
    if (brightnessDb != 0.0) m = _applyBrightness(m, brightnessDb, sampleRate);
    if (tension > 0.0) m = _applyTension(m, tension);
    if (breathiness > 0.0) m = _applyBreathiness(m, breathiness);
    if (speedRatio != 1.0) {
      final stretched = _timeStretch(m, p, nf, speedRatio);
      m = stretched.$1;
      p = stretched.$2;
      nf = stretched.$3;
    }

    final result = _istft(m, p, nf);

    // Peak normalize
    double maxVal = 0;
    for (final s in result) {
      if (s.abs() > maxVal) maxVal = s.abs();
    }
    if (maxVal > 0) {
      final scale = _peak / maxVal;
      for (int i = 0; i < result.length; i++) {
        result[i] *= scale;
      }
    }
    return result;
  }

  // ── FFT (radix-2, decimation-in-time, in-place) ──────────────

  static void _fft(Float64List real, Float64List imag) {
    final n = real.length;
    int j = 0;
    for (int i = 0; i < n - 1; i++) {
      if (i < j) {
        var t = real[i]; real[i] = real[j]; real[j] = t;
        t = imag[i]; imag[i] = imag[j]; imag[j] = t;
      }
      int k = n >> 1;
      while (k <= j) { j -= k; k >>= 1; }
      j += k;
    }
    for (int len = 2; len <= n; len <<= 1) {
      final half = len >> 1;
      final ang = -2 * pi / len;
      for (int i = 0; i < n; i += len) {
        for (int k = 0; k < half; k++) {
          final wr = cos(ang * k);
          final wi = sin(ang * k);
          final tr = real[i + k + half] * wr - imag[i + k + half] * wi;
          final ti = real[i + k + half] * wi + imag[i + k + half] * wr;
          real[i + k + half] = real[i + k] - tr;
          imag[i + k + half] = imag[i + k] - ti;
          real[i + k] += tr;
          imag[i + k] += ti;
        }
      }
    }
  }

  static void _ifft(Float64List real, Float64List imag) {
    final n = real.length;
    for (int i = 0; i < n; i++) {
      imag[i] = -imag[i];
    }
    _fft(real, imag);
    for (int i = 0; i < n; i++) {
      real[i] /= n;
      imag[i] = -imag[i] / n;
    }
  }

  // ── Hann window ──────────────────────────────────────────────

  static Float64List _hann(int size) {
    final w = Float64List(size);
    for (int i = 0; i < size; i++) {
      w[i] = 0.5 * (1 - cos(2 * pi * i / (size - 1)));
    }
    return w;
  }

  // ── STFT ─────────────────────────────────────────────────────

  static (Float64List mag, Float64List phase, int numFrames) _stft(
    Float64List samples,
  ) {
    final window = _hann(_nfft);
    final numFrames = ((samples.length - _nfft) / _hop).floor() + 1;
    if (numFrames <= 0) return (Float64List(0), Float64List(0), 0);

    final mag = Float64List(numFrames * _bins);
    final phase = Float64List(numFrames * _bins);
    final re = Float64List(_nfft);
    final im = Float64List(_nfft);

    for (int t = 0; t < numFrames; t++) {
      final off = t * _hop;
      for (int i = 0; i < _nfft; i++) {
        final v = off + i < samples.length ? samples[off + i] : 0;
        re[i] = v * window[i];
        im[i] = 0;
      }
      _fft(re, im);
      for (int b = 0; b < _bins; b++) {
        mag[t * _bins + b] = sqrt(re[b] * re[b] + im[b] * im[b]);
        phase[t * _bins + b] = atan2(im[b], re[b]);
      }
    }
    return (mag, phase, numFrames);
  }

  // ── ISTFT ───────────────────────────────────────────────────

  static Float64List _istft(
    Float64List mag, Float64List phase, int numFrames,
  ) {
    final window = _hann(_nfft);
    final outLen = (numFrames - 1) * _hop + _nfft;
    final out = Float64List(outLen);
    final sumWin = Float64List(outLen);
    final re = Float64List(_nfft);
    final im = Float64List(_nfft);

    for (int t = 0; t < numFrames; t++) {
      for (int b = 0; b < _bins; b++) {
        final m = mag[t * _bins + b];
        final p = phase[t * _bins + b];
        re[b] = m * cos(p);
        im[b] = m * sin(p);
      }
      for (int b = 1; b < _bins - 1; b++) {
        final m = mag[t * _bins + b];
        final p = phase[t * _bins + b];
        re[_nfft - b] = m * cos(p);
        im[_nfft - b] = -m * sin(p);
      }
      _ifft(re, im);
      final off = t * _hop;
      for (int i = 0; i < _nfft; i++) {
        final v = re[i] * window[i];
        out[off + i] += v;
        sumWin[off + i] += window[i] * window[i];
      }
    }
    for (int i = 0; i < outLen; i++) {
      if (sumWin[i] > 1e-10) out[i] /= sumWin[i];
    }
    return out;
  }

  // ── Pitch shift ──────────────────────────────────────────────

  static Float64List _pitchShift(Float64List mag, double semitones) {
    final nf = mag.length ~/ _bins;
    final shift = pow(2.0, semitones / 12.0).toDouble();
    final out = Float64List(mag.length);
    for (int t = 0; t < nf; t++) {
      final off = t * _bins;
      for (int b = 0; b < _bins; b++) {
        final src = (b / shift).round();
        out[off + b] = (src >= 0 && src < _bins) ? mag[off + src] : 0;
      }
    }
    return out;
  }

  // ── Pitch variance ──────────────────────────────────────────

  static Float64List _applyPitchVariance(Float64List mag, double scale) {
    final nf = mag.length ~/ _bins;
    final out = Float64List(mag.length);
    for (int t = 0; t < nf; t++) {
      final off = t * _bins;
      double energy = 0;
      for (int b = 0; b < _bins; b++) {
        energy += mag[off + b].abs();
      }
      energy = energy / _bins;
      final mod = 1.0 + (scale - 1.0) * energy;
      for (int b = 0; b < _bins; b++) {
        out[off + b] = mag[off + b] * mod;
      }
    }
    return out;
  }

  // ── Brightness ──────────────────────────────────────────────

  static Float64List _applyBrightness(
    Float64List mag, double db, int sampleRate,
  ) {
    final nf = mag.length ~/ _bins;
    final nyquist = sampleRate / 2.0;
    final gain = Float64List(_bins);
    for (int b = 0; b < _bins; b++) {
      final frac = (b * nyquist / (_bins - 1)) / nyquist;
      gain[b] = pow(10.0, db * frac / 20.0).toDouble();
    }
    final out = Float64List(mag.length);
    for (int t = 0; t < nf; t++) {
      final off = t * _bins;
      for (int b = 0; b < _bins; b++) {
        out[off + b] = mag[off + b] * gain[b];
      }
    }
    return out;
  }

  // ── Tension ─────────────────────────────────────────────────

  static Float64List _applyTension(Float64List mag, double amount) {
    final nf = mag.length ~/ _bins;
    final out = Float64List(mag.length);
    for (int t = 0; t < nf; t++) {
      final off = t * _bins;
      final smooth = Float64List(_bins);
      for (int b = 2; b < _bins - 2; b++) {
        smooth[b] = (mag[off + b - 2] + mag[off + b - 1] + mag[off + b] +
            mag[off + b + 1] + mag[off + b + 2]) / 5.0;
      }
      smooth[0] = mag[off];
      smooth[1] = _bins > 1 ? mag[off + 1] : 0;
      if (_bins > 2) smooth[_bins - 2] = mag[off + _bins - 2];
      if (_bins > 1) smooth[_bins - 1] = mag[off + _bins - 1];
      for (int b = 0; b < _bins; b++) {
        final diff = mag[off + b] - smooth[b];
        out[off + b] = smooth[b] + diff * (1.0 + amount);
      }
    }
    return out;
  }

  // ── Breathiness ─────────────────────────────────────────────

  static Float64List _applyBreathiness(Float64List mag, double amount) {
    final nf = mag.length ~/ _bins;
    final lowBin = _bins ~/ 4;
    final rng = Random(42);
    final out = Float64List(mag.length);
    for (int t = 0; t < nf; t++) {
      final off = t * _bins;
      double energy = 0;
      for (int b = lowBin; b < _bins; b++) {
        energy += mag[off + b].abs();
      }
      energy = (energy / (_bins - lowBin)) * amount;
      for (int b = 0; b < _bins; b++) {
        if (b < lowBin) {
          out[off + b] = mag[off + b];
        } else {
          out[off + b] = mag[off + b] + (rng.nextDouble() * 2 - 1) * energy;
        }
      }
    }
    return out;
  }

  // ── Time stretch ────────────────────────────────────────────

  static (Float64List, Float64List, int) _timeStretch(
    Float64List mag, Float64List phase, int numFrames, double ratio,
  ) {
    final newFrames = (numFrames / ratio).round();
    if (newFrames < 1) return (mag, phase, numFrames);
    final outMag = Float64List(newFrames * _bins);
    final outPhase = Float64List(newFrames * _bins);
    for (int t = 0; t < newFrames; t++) {
      final src = (t * ratio).floor();
      final frac = (t * ratio) - src;
      final nxt = (src + 1).clamp(0, numFrames - 1);
      final clp = src.clamp(0, numFrames - 1);
      for (int b = 0; b < _bins; b++) {
        final m1 = mag[clp * _bins + b];
        final m2 = mag[nxt * _bins + b];
        outMag[t * _bins + b] = m1 + (m2 - m1) * frac;
        outPhase[t * _bins + b] = phase[clp * _bins + b];
      }
    }
    return (outMag, outPhase, newFrames);
  }
}
