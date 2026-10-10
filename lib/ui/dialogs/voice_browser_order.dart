// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/services.dart';

/// Voice Model Browser row order: the voices that were installed when the
/// browser opened come first, then by language, then by name.
///
/// Keyed on the installs at OPEN, not the live set: a voice that finishes
/// downloading (or is deleted) keeps its row, so the button under the
/// pointer never turns into another voice's Download button.
void sortVoiceRows(List<PiperVoice> rows, Set<String> installedAtOpen) {
  rows.sort((a, b) {
    final aFirst = installedAtOpen.contains(a.key);
    final bFirst = installedAtOpen.contains(b.key);
    if (aFirst != bFirst) return aFirst ? -1 : 1;
    final byLanguage = a.languageEnglish.compareTo(b.languageEnglish);
    if (byLanguage != 0) return byLanguage;
    return a.name.compareTo(b.name);
  });
}
