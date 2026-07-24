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

/// Dreams (living-time-features.md §1) — when the story crosses a night, the
/// character dreams, seeded ONLY from what the Journal already says mattered
/// (plus fixation/mood/weather). Pure domain leaf: rollover bookkeeping,
/// prompt building, and the skip-on-garbage floor. All cross-state arrives
/// via callbacks; the god stays the thin glue (CLAUDE.md extraction rule).
class DreamService {
  /// Fires one eval (LlmEvalEngine fire + central think-strip, wired by the
  /// host) and returns the raw text, or null on backend failure.
  final Future<String?> Function(String prompt) fireEval;

  /// Effective gate: realism + journal + passage-of-time + the dreams toggle.
  final bool Function() isEnabled;

  DreamService({required this.fireEval, required this.isEnabled});

  String? _markerSession;
  int _lastDay = 0;
  bool _pending = false;

  bool get pending => _pending;

  /// Session-scoped rollover bookkeeping — ONE call site (sendMessage entry)
  /// and no per-load seeding: an unseen session re-anchors silently, so a
  /// fresh load can never fire a dream for days that passed while the app
  /// was closed (story time only moves while you play).
  void checkRollover({required String? sessionId, required int dayCount}) {
    if (sessionId == null) return;
    if (sessionId != _markerSession) {
      _markerSession = sessionId;
      _lastDay = dayCount;
      _pending = false;
      return;
    }
    if (dayCount > _lastDay && isEnabled()) _pending = true;
    if (dayCount != _lastDay) _lastDay = dayCount;
  }

  void clear() => _pending = false;

  /// One short call; returns sanitized dream text or null (skip silently —
  /// the local-model floor: a bad dream is worse than no dream).
  Future<String?> generateDream({
    required String characterName,
    required List<String> memoryFragments,
    String? fixation,
    required String emotion,
    required String recap,
    String? weatherLine,
    List<String> ambitions = const [],
  }) async {
    final fragments = memoryFragments
        .take(5)
        .map((m) => '- $m')
        .join('\n');
    final ambitionLine = ambitions.isEmpty
        ? ''
        : 'Long-held ambition (aspiration or anxiety may color the dream): '
            '${ambitions.first}\n';
    final prompt =
        'Write the dream $characterName had last night: a brief, hazy, '
        'first-person dream of two to four sentences.\n\n'
        'Weave in fragments of what actually occupies $characterName:\n'
        '${fragments.isEmpty ? '- (no strong memories yet — keep it vague and atmospheric)' : fragments}\n'
        '${fixation != null && fixation.isNotEmpty ? 'Current fixation: $fixation\n' : ''}'
        '$ambitionLine'
        '${emotion.isNotEmpty ? 'Mood carried to sleep: $emotion\n' : ''}'
        '${weatherLine != null && weatherLine.isNotEmpty ? 'Outside: $weatherLine\n' : ''}'
        '${recap.isNotEmpty ? 'Where the story stands: $recap\n' : ''}'
        '\nRules: first person as $characterName; dreamlike, associative, '
        'slightly surreal; reference ONLY the fragments above — invent no '
        'new people, facts, or events; no dialogue quotes; two to four '
        'sentences. Output ONLY the dream text, nothing else.';

    final raw = await fireEval(prompt);
    return _sanitize(raw);
  }

  /// Skip-on-garbage floor: strip wrappers, then reject anything too short
  /// to be a dream or long enough to be a runaway generation.
  static String? _sanitize(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    // Strip a wrapping code fence or quote pair the model may add.
    text = text
        .replaceFirst(RegExp(r'^```[a-z]*\n?'), '')
        .replaceFirst(RegExp(r'\n?```$'), '')
        .trim();
    if (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      text = text.substring(1, text.length - 1).trim();
    }
    // A leading "Dream:" / "Name:" label from literal-minded models.
    text = text.replaceFirst(
      RegExp(r'^[A-Za-z ]{1,24}:\s+(?=[A-Z"I])'),
      '',
    );
    if (text.length < 30 || text.length > 700) return null;
    return text;
  }
}
