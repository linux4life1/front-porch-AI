// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int _kMaxHeaderBytes = 64 * 1024 * 1024;

const _kEncoderPrefixes = [
  'text_encoders.',
  'text_encoder.',
  'cond_stage_model.',
  'conditioner.',
];

const _kVaePrefixes = ['vae.', 'first_stage_model.'];

/// Tensor names in a `.safetensors` header, or null when the file is not one.
/// Only the header is read, never the weights.
Future<List<String>?> safetensorsTensorNames(File file) async {
  RandomAccessFile? handle;
  try {
    handle = await file.open();
    final size = await handle.length();
    if (size < 8) return null;
    final lead = await handle.read(8);
    final length = ByteData.sublistView(
      Uint8List.fromList(lead),
    ).getUint64(0, Endian.little);
    if (length <= 0 || length > _kMaxHeaderBytes || 8 + length > size) {
      return null;
    }
    final header = await handle.read(length);
    final decoded = jsonDecode(utf8.decode(header));
    if (decoded is! Map) return null;
    return [
      for (final key in decoded.keys)
        if (key != '__metadata__') key.toString(),
    ];
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  } finally {
    await handle?.close();
  }
}

/// True when the weights carry their own text encoder and VAE, which is what
/// ComfyUI's checkpoint loader reads. A bare diffusion model has neither.
Future<bool> safetensorsIsAllInOne(File file) async {
  final names = await safetensorsTensorNames(file);
  if (names == null) return false;
  bool has(List<String> prefixes) =>
      names.any((name) => prefixes.any(name.startsWith));
  return has(_kEncoderPrefixes) && has(_kVaePrefixes);
}
