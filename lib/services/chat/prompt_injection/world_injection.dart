// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World description injection — makes a world a *place* the character inhabits.
// Budget-capped; only worlds with injectDescription == true contribute.

import 'package:front_porch_ai/models/world.dart';

/// Soft token budget for world place prose (approx chars / 4).
const int kWorldInjectionMaxChars = 600;

/// Build a scene-setting block from attached worlds' descriptions.
/// Empty when nothing should inject.
String buildWorldInjection(List<World> worlds) {
  final parts = <String>[];
  var used = 0;
  for (final w in worlds) {
    if (!w.injectDescription) continue;
    final desc = w.description.trim();
    if (desc.isEmpty) continue;
    final header = w.name.trim().isEmpty ? 'This place' : w.name.trim();
    final block = '$header: $desc';
    if (used + block.length > kWorldInjectionMaxChars) {
      final remain = kWorldInjectionMaxChars - used;
      if (remain < 40) break;
      parts.add(block.substring(0, remain).trimRight());
      break;
    }
    parts.add(block);
    used += block.length + 1;
  }
  if (parts.isEmpty) return '';
  return 'Setting — where you are:\n${parts.join('\n')}';
}
