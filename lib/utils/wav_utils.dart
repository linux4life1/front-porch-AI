// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// WAV file utilities.

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class WavUtils {
  /// Concatenate multiple WAV files into a single WAV file.
  /// All files must have the same format (sample rate, channels, bit depth).
  static Future<File?> concatenateWavFiles(List<File> wavFiles) async {
    if (wavFiles.isEmpty) return null;
    if (wavFiles.length == 1) return wavFiles.first;

    try {
      final firstBytes = await wavFiles.first.readAsBytes();
      if (firstBytes.length < 44) return null;

      final bd = ByteData.sublistView(firstBytes);
      final sampleRate = bd.getUint32(24, Endian.little);
      final channels = bd.getUint16(22, Endian.little);
      final bitsPerSample = bd.getUint16(34, Endian.little);
      final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
      final blockAlign = channels * (bitsPerSample ~/ 8);

      final pcmChunks = <Uint8List>[];
      int totalPcmBytes = 0;

      for (final file in wavFiles) {
        final bytes = await file.readAsBytes();
        if (bytes.length <= 44) continue;

        int dataOffset = 12;
        while (dataOffset < bytes.length - 8) {
          final chunkId = String.fromCharCodes(bytes.sublist(dataOffset, dataOffset + 4));
          final chunkSize = ByteData.sublistView(bytes).getUint32(dataOffset + 4, Endian.little);
          if (chunkId == 'data') {
            final pcmStart = dataOffset + 8;
            final pcmEnd = (pcmStart + chunkSize).clamp(0, bytes.length);
            final pcm = bytes.sublist(pcmStart, pcmEnd);
            pcmChunks.add(Uint8List.fromList(pcm));
            totalPcmBytes += pcm.length;
            break;
          }
          dataOffset += 8 + chunkSize;
        }
      }

      if (totalPcmBytes == 0) return null;

      final fileSize = 36 + totalPcmBytes;
      final header = ByteData(44);
      // RIFF
      header.setUint8(0, 0x52); header.setUint8(1, 0x49);
      header.setUint8(2, 0x46); header.setUint8(3, 0x46);
      header.setUint32(4, fileSize, Endian.little);
      header.setUint8(8, 0x57); header.setUint8(9, 0x41);
      header.setUint8(10, 0x56); header.setUint8(11, 0x45);
      // fmt
      header.setUint8(12, 0x66); header.setUint8(13, 0x6D);
      header.setUint8(14, 0x74); header.setUint8(15, 0x20);
      header.setUint32(16, 16, Endian.little);
      header.setUint16(20, 1, Endian.little);
      header.setUint16(22, channels, Endian.little);
      header.setUint32(24, sampleRate, Endian.little);
      header.setUint32(28, byteRate, Endian.little);
      header.setUint16(32, blockAlign, Endian.little);
      header.setUint16(34, bitsPerSample, Endian.little);
      // data
      header.setUint8(36, 0x64); header.setUint8(37, 0x61);
      header.setUint8(38, 0x74); header.setUint8(39, 0x61);
      header.setUint32(40, totalPcmBytes, Endian.little);

      final tempDir = Directory.systemTemp;
      final combinedFile = File(p.join(tempDir.path,
          'tts_combined_${DateTime.now().millisecondsSinceEpoch}.wav'));
      final sink = combinedFile.openWrite();
      sink.add(header.buffer.asUint8List());
      for (final chunk in pcmChunks) {
        sink.add(chunk);
      }
      await sink.close();

      return combinedFile;
    } catch (e) {
      print('Error concatenating WAV files: $e');
      return null;
    }
  }
}
