// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

/// Pure-Dart WAV resampler using linear interpolation.
///
/// Applies the "tape speed" trick: changes both pitch and duration by the same
/// factor without any signal-processing artifacts.  A factor > 1 speeds up
/// (higher pitch, shorter), a factor < 1 slows down (lower pitch, longer).
class WavResampler {
  /// Resample [input] by [rate] and write the result to a new temp file.
  ///
  /// Returns the new file, or [input] unchanged when [rate] == 1.0 (the common
  /// case for neutral / unmapped emotions).
  static Future<File> resample(File input, double rate) async {
    if (rate == 1.0) return input;

    final bytes = await input.readAsBytes();
    if (bytes.length < 44) return input;

    final bd = ByteData.sublistView(bytes);

    // Parse WAV header
    final channels = bd.getUint16(22, Endian.little);
    final sampleRate = bd.getUint32(24, Endian.little);
    final bitsPerSample = bd.getUint16(34, Endian.little);
    final bytesPerSample = bitsPerSample ~/ 8;

    // Find 'data' sub-chunk
    int dataOffset = 12;
    int pcmSize = 0;
    while (dataOffset < bytes.length - 8) {
      final chunkId = String.fromCharCodes(
        bytes.sublist(dataOffset, dataOffset + 4),
      );
      final chunkSize = bd.getUint32(dataOffset + 4, Endian.little);
      if (chunkId == 'data') {
        pcmSize = chunkSize;
        dataOffset += 8;
        break;
      }
      dataOffset += 8 + chunkSize;
    }
    if (pcmSize == 0) return input;

    final pcmStart = dataOffset;
    final pcmEnd = (pcmStart + pcmSize).clamp(0, bytes.length);
    final pcmBytes = bytes.sublist(pcmStart, pcmEnd);

    // Number of source frames (interleaved samples per channel)
    final frameSize = channels * bytesPerSample;
    final srcFrames = pcmBytes.length ~/ frameSize;
    if (srcFrames == 0) return input;

    final invRate = 1.0 / rate;
    final dstFrames = (srcFrames * invRate).round();
    if (dstFrames == 0) return input;

    final dst = Uint8List(dstFrames * frameSize);
    final dstBd = ByteData.sublistView(dst);

    for (int i = 0; i < dstFrames; i++) {
      final srcPos = i * rate;
      final lo = srcPos.floor();
      final hi = (lo + 1).clamp(0, srcFrames - 1);
      final frac = srcPos - lo;

      for (int ch = 0; ch < channels; ch++) {
        final srcIdxLo = lo * frameSize + ch * bytesPerSample;
        final srcIdxHi = hi * frameSize + ch * bytesPerSample;
        final dstIdx = i * frameSize + ch * bytesPerSample;

        if (bytesPerSample == 2) {
          final sLo = bd.getInt16(pcmStart + srcIdxLo, Endian.little);
          final sHi = bd.getInt16(pcmStart + srcIdxHi, Endian.little);
          final sample = sLo + ((sHi - sLo) * frac).round();
          dstBd.setInt16(
            dstIdx,
            sample.clamp(-32768, 32767),
            Endian.little,
          );
        } else if (bytesPerSample == 1) {
          final sLo = bytes[pcmStart + srcIdxLo].toInt();
          final sHi = bytes[pcmStart + srcIdxHi].toInt();
          final sample = sLo + ((sHi - sLo) * frac).round();
          dst[dstIdx] = sample.clamp(0, 255);
        }
      }
    }

    // Build new WAV file
    final newPcmSize = dst.length;
    final fileSize = 36 + newPcmSize;
    final byteRate = sampleRate * channels * bytesPerSample;
    final blockAlign = channels * bytesPerSample;

    final header = ByteData(44);
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, newPcmSize, Endian.little);

    final outputPath = p.join(
      Directory.systemTemp.path,
      'emotional_voice_${DateTime.now().millisecondsSinceEpoch}_${input.hashCode}.wav',
    );
    final output = File(outputPath);
    final sink = output.openWrite();
    sink.add(header.buffer.asUint8List());
    sink.add(dst);
    await sink.close();

    return output;
  }
}
