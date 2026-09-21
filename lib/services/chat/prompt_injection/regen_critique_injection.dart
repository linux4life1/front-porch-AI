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

import 'package:front_porch_ai/services/chat/prompt_injection/search_injection.dart';

/// Spoken clip of the rejected swipe (~200 tokens at 4 chars/token).
const int kRegenCritiqueClipCharCap = kSearchSnippetCharCap;

/// User's free-form reject reason.
const int kRegenCritiqueReasonCharCap = 500;

/// One-shot director slip for a Regen that carries a reject reason.
/// Empty / whitespace reason → no section (byte-identical to today's regen).
/// Never written into `messages`; lives on that swipe's prompt only.
class RegenCritiqueInjection {
  RegenCritiqueInjection._();

  static final RegExp _closedThink = RegExp(
    r'<think>[\s\S]*?</think>',
    caseSensitive: false,
  );
  static final RegExp _openThink = RegExp(
    r'<think>[\s\S]*$',
    caseSensitive: false,
  );
  static final RegExp _delimiters = RegExp(r'[\[\]{}"<>]');

  /// Prompt section text, or empty when there is nothing to inject.
  static String fragment({required String spokenText, required String reason}) {
    final cleanedReason = sanitizeReason(reason);
    if (cleanedReason.isEmpty) return '';
    final clip = clipSpoken(spokenText);
    if (clip.isEmpty) return '';
    return '[Director note — this swipe only. Not a user line. '
        'The previous take is rejected; do not treat it as canon. '
        'Write a new in-character reply.\n'
        'Critique: $cleanedReason\n'
        'Rejected take (clip): $clip]\n';
  }

  /// Think-stripped, HTML/URL-cleaned, delimiter-stripped, 800-char clip.
  static String clipSpoken(String input) {
    var s = _stripThink(input);
    s = SearchInjection.clipSnippet(s);
    return _stripDelimiters(s);
  }

  /// Prompt-safe reject reason, capped at [kRegenCritiqueReasonCharCap].
  static String sanitizeReason(String input) {
    var s = _stripThink(input);
    s = s.replaceAll(RegExp(r'<[^>]*>'), '');
    s = _stripDelimiters(s);
    if (s.length <= kRegenCritiqueReasonCharCap) return s;
    return s.substring(0, kRegenCritiqueReasonCharCap).trim();
  }

  static String _stripThink(String input) {
    var s = input.replaceAll(_closedThink, ' ');
    return s.replaceAll(_openThink, ' ');
  }

  static String _stripDelimiters(String input) {
    var s = input.replaceAll(_delimiters, ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
