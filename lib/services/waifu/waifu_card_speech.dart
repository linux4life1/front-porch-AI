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

// Speech-only honesty. Card diction is the model's job; this layer
// forbids wrap-up from inventing tool or verify success.

enum WaifuSpeechKind { wrapUp, checkIn, stuck }

/// Wrap-up / check-in / stuck: card voice, never a fake receipt.
const kWaifuSpeechHonestyCue =
    'Speak wrap-up, check-in, and stuck lines in the selected card’s '
    'diction. Never claim a tool, write, patch, or test succeeded '
    'unless this turn has a receipt for it. No receipt means you '
    'cannot claim success. Generic “Done”, an empty answer, or a '
    'denied write is not completion.';

String waifuSpeechKindCue(WaifuSpeechKind kind) {
  final lead = switch (kind) {
    WaifuSpeechKind.wrapUp =>
      'WRAP-UP: One short in-character line now. No tool call.',
    WaifuSpeechKind.checkIn =>
      'CHECK-IN: One short in-character line after the check passes.',
    WaifuSpeechKind.stuck =>
      'STUCK: Stay in character and tell the truth about the stop.',
  };
  return '$lead $kWaifuSpeechHonestyCue';
}

/// Coaching / lookup / verify *cues* must not name the host-app stack.
/// Sit-down markers may still detect Flutter; this is the prompt leak.
bool waifuCoachingLeaksHostStack(String text) {
  final lower = text.toLowerCase();
  return lower.contains('flutter') ||
      lower.contains('dart analyze') ||
      lower.contains('dart test') ||
      lower.contains('docs.flutter') ||
      lower.contains('pub.dev') ||
      lower.contains('dart.dev');
}

bool _waifuLooksHonestFailure(String lower) {
  return RegExp(
    r"\b(could not|couldn't|did not|didn't|cannot|can't|failed to|"
    r'never ran|no (?:file )?change|stopped instead)\b',
  ).hasMatch(lower);
}

/// Peel short card interjections so “Hmph. Done. Obviously.” is still Done.
String waifuStripCardWrappers(String body) {
  var t = body.trim();
  final lead = RegExp(r"^[\w']{1,16}[,.!…—-]+\s*", caseSensitive: false);
  final tail = RegExp(r"\s+[\w']{1,16}[.!…]*$", caseSensitive: false);
  final commaTail = RegExp(r',?\s+[\w]{1,16}$', caseSensitive: false);
  for (var i = 0; i < 3; i++) {
    final next = t.replaceFirst(lead, '').trim();
    if (next == t) break;
    t = next;
  }
  for (var i = 0; i < 3; i++) {
    final next = t.replaceFirst(tail, '').trim();
    if (next == t) break;
    t = next;
  }
  final comma = t.replaceFirst(commaTail, '').trim();
  if (comma.isNotEmpty) t = comma;
  return t;
}

/// File-change success in English — card wrappers do not hide it.
bool waifuLooksMutateSuccessClaim(String body) {
  final lower = body.toLowerCase();
  if (_waifuLooksHonestFailure(lower)) return false;
  if (RegExp(r'\b(?:todo|to-do)s?\b').hasMatch(lower)) return false;
  return RegExp(
        r'\b(wrote|patched|edited|applied(?: the)?(?: patch| changes)?|'
        r'saved|fixed|implemented|created|landed|scaffolded)\b',
      ).hasMatch(lower) ||
      RegExp(
        r"\b(?:it'?s|it is) (?:in|fixed|done|patched)\b",
      ).hasMatch(lower) ||
      RegExp(r'\bconsider it (?:fixed|done)\b').hasMatch(lower);
}

/// Verify success in English — card wrappers do not hide it.
bool waifuLooksVerifySuccessClaim(String body) {
  final lower = body.toLowerCase();
  if (_waifuLooksHonestFailure(lower)) return false;
  return RegExp(
    r'\b(tests? (?:passed|pass|are green|are clean)|'
    r'analyze (?:passed|is clean|came back clean)|'
    r'verified|verification passed|check(?:s)? passed|no issues)\b',
  ).hasMatch(lower);
}

bool waifuLooksReceiptSuccessClaim(String body) =>
    waifuLooksMutateSuccessClaim(body) || waifuLooksVerifySuccessClaim(body);

/// Fallback porch line. Never a success claim — card voice is the model's.
String waifuHonestFallbackSpeech(String line, String stuck) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return stuck;
  if (waifuLooksReceiptSuccessClaim(trimmed) &&
      !_waifuLooksHonestFailure(trimmed.toLowerCase())) {
    return stuck;
  }
  return trimmed;
}
