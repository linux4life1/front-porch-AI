// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/services.dart';

/// A Piper voice the way the Voice Model Browser describes it — "amy,
/// English (United States), medium" — instead of its file name
/// "en_US-amy-medium". A voice the catalog does not know (a custom import)
/// keeps its file name, which is the name the user gave it.
String piperVoiceLabel(String key, Iterable<PiperVoice> catalog) {
  for (final v in catalog) {
    if (v.key != key) continue;
    final place = v.countryEnglish.isEmpty
        ? v.languageEnglish
        : '${v.languageEnglish} (${v.countryEnglish})';
    final parts = [v.name, place, v.quality].where((s) => s.isNotEmpty);
    return parts.isEmpty ? key : parts.join(', ');
  }
  return key;
}
