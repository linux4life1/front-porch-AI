// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

/// How many LoRAs one generation can stack. The Studio shows the first
/// [kImageGenLoraVisibleSlots] and tucks the rest in an accordion.
const int kImageGenLoraSlotCount = 8;
const int kImageGenLoraVisibleSlots = 4;

/// One LoRA file plus its strength. An empty [file] is an unused slot.
class ImageGenLoraSlot {
  final String file;
  final double weight;

  const ImageGenLoraSlot({this.file = '', this.weight = 0.8});

  bool get isEmpty => file.trim().isEmpty;

  ImageGenLoraSlot copyWith({String? file, double? weight}) =>
      ImageGenLoraSlot(file: file ?? this.file, weight: weight ?? this.weight);

  static List<ImageGenLoraSlot> blank() =>
      List.filled(kImageGenLoraSlotCount, const ImageGenLoraSlot());

  /// Pad or trim to [kImageGenLoraSlotCount].
  static List<ImageGenLoraSlot> fit(List<ImageGenLoraSlot> slots) {
    final out = blank();
    final n = slots.length < out.length ? slots.length : out.length;
    for (var i = 0; i < n; i++) {
      out[i] = ImageGenLoraSlot(
        file: slots[i].file,
        weight: slots[i].weight.clamp(0.0, 1.0),
      );
    }
    return out;
  }

  static String encode(List<ImageGenLoraSlot> slots) => jsonEncode([
    for (final s in fit(slots)) {'file': s.file, 'weight': s.weight},
  ]);

  /// [raw] is the `image_gen_loras` JSON. When it is missing, slot 0 is the
  /// old single `image_gen_lora` name so existing libraries keep their LoRA.
  static List<ImageGenLoraSlot> decode(
    String? raw, {
    String legacyFile = '',
    double legacyWeight = 0.8,
  }) {
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return fit([
            for (final row in decoded)
              if (row is Map)
                ImageGenLoraSlot(
                  file: row['file']?.toString() ?? '',
                  weight: (row['weight'] as num?)?.toDouble() ?? 0.8,
                ),
          ]);
        }
      } catch (_) {
        // Fall through to the single-slot keys.
      }
    }
    final out = blank();
    if (legacyFile.trim().isNotEmpty) {
      out[0] = ImageGenLoraSlot(
        file: legacyFile,
        weight: legacyWeight.clamp(0.0, 1.0),
      );
    }
    return out;
  }
}

/// Automatic1111 applies every filled slot as a prompt tag.
String promptWithLoras(String prompt, List<ImageGenLoraSlot> slots) {
  final tags = [
    for (final s in slots)
      if (!s.isEmpty) '<lora:${s.file.trim()}:${s.weight.toStringAsFixed(2)}>',
  ];
  if (tags.isEmpty) return prompt;
  return '$prompt ${tags.join(' ')}';
}
