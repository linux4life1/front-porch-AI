// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:front_porch_ai/services/storage/settings/generation_settings.dart';

/// How many stop strings the local KoboldCpp transport sends server-side.
/// KoboldCpp maps the OpenAI `stop` array onto its native stop_sequence
/// machinery, whose cap is `stop_token_max = 256` in current koboldcpp.py
/// (raised in v1.77); 16 is kept as a safe floor for older builds users may
/// still run. Anything beyond the server cap is still enforced by the
/// client-side mid-stream trim in `_generateResponse`.
const int kMaxLocalServerStops = 16;

/// Builds the generation stop-sequence list in priority order, so that when a
/// transport can only send the first N entries (remote providers commonly cap
/// `stop` at 4), the most important ones survive
/// (docs/design/prompt-state-injection.md §5e):
///
///  1. User-side stops — `\nUser:` + `\n<persona name>:` — the model writing
///     the human's turn is the worst failure. Skipped when impersonating
///     (the model IS the user on that path).
///  2. User-configured custom stops (explicit intent outranks generated
///     entries). The stored settings list mixes shipped defaults with user
///     additions; anything not in [GenerationSettings.kDefaultStopSequences]
///     is a user addition.
///  3. Character-name stops, in the caller's order (group callers pass the
///     roster rotated so the soonest next speakers come first). The
///     continue-mode speaker is excluded so Continue can extend their message.
///  4. The shipped template-end defaults that remain in the configured list.
///
/// Before this existed, the assembly used insertion-ordered sets starting with
/// the defaults, and the transports' `take(4)` meant custom stops and every
/// name-stop likely NEVER reached the server — the client-side trim hid it
/// while the server generated on past the boundary.
List<String> buildPrioritizedStops({
  required List<String> configured,
  required String userName,
  bool impersonating = false,
  List<String> characterNames = const [],
  String? continueSpeakerName,
}) {
  // Set semantics (insertion-ordered) so a string keeps its highest priority
  // even when it appears again lower down (e.g. `\nUser:` is also a default).
  final ordered = <String>{};

  if (!impersonating) {
    ordered.add('\nUser:');
    final trimmedName = userName.trim();
    if (trimmedName.isNotEmpty) ordered.add('\n$trimmedName:');
  }

  const defaults = GenerationSettings.kDefaultStopSequences;
  for (final s in configured) {
    if (!defaults.contains(s)) ordered.add(s);
  }

  for (final name in characterNames) {
    if (continueSpeakerName != null && name == continueSpeakerName) continue;
    ordered.add('\n$name:');
  }

  for (final s in configured) {
    if (defaults.contains(s)) ordered.add(s);
  }

  return ordered.toList();
}
