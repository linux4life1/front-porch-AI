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

/// ~200 tokens of snippet text. 4 chars/token is the same estimate the
/// rest of prompt budgeting uses.
const int kWebSearchSnippetCharCap = 800;
const int kSearchSnippetCharCap = kWebSearchSnippetCharCap;

/// Standing character-prompt line while Web Search is on for this chat.
const String kWebSearchCharacterLine =
    'When a search result gives you new information, react to it as yourself '
    '— your personality, your voice, your emotions. Don\'t recite the source. '
    'Don\'t break character. You simply know the thing now.';
const String kSearchCharacterLine = kWebSearchCharacterLine;

/// Tools-round-only cue. This round is a silent think-to-search check,
/// not the character reply — without that split, RP completion ending in
/// `Name:` just talks unless the user OOC-forces a lookup.
const String kWebSearchDecisionCue =
    '[This is a silent lookup check, not your reply. Think: does the last '
    'user message name something you are not certain of — a person, place, '
    'show, character, book, lore, term, weather, news, date, or anything '
    'you do not recognize? Fiction counts. If yes, call web_search with '
    'that query. The call is silent; you are not breaking character. Do '
    'not guess. If you already know it from your character or the scene, '
    'or it is just conversation, call nothing. Do not write the reply yet.]';

/// Last-token wrap so the cue beats the `Name:` suffix on local models.
String webSearchDecisionPrompt(String prompt) =>
    '$prompt\n\n$kWebSearchDecisionCue';

/// System wrap so remote models that ignore the user-tail still see it.
String webSearchDecisionSystemPrompt(String? systemPrompt) {
  final base = systemPrompt?.trim() ?? '';
  if (base.isEmpty) return kWebSearchDecisionCue;
  return '$base\n\n$kWebSearchDecisionCue';
}

/// Gated character fragments for a web_search result. Speaker sees them;
/// they are not written into the bubble or the user's lorebook.
class SearchInjection {
  SearchInjection._();

  static String emptyResultFragment(String query) {
    return 'You found no reliable information about "$query". '
        'You do not know this. Do not invent. Say you don\'t know.';
  }

  static String emptyResult(String query) => emptyResultFragment(query);

  static String resultFragment(String snippet) {
    final cleaned = clipSnippet(snippet);
    return '[WHAT YOU KNOW — not spoken aloud, not a source to cite; '
        'you simply know this now. These are facts, not a calendar. '
        'Do not speak a weekday, date, or year from the notes — ignore '
        'those if they appear. The scene\'s date and time are unchanged. '
        'If a detail is not in this, you do not know it. Do not invent '
        'a weekday, a number, or a name that is not here:\n$cleaned\n]';
  }

  /// Snippet text only: strip HTML and URLs, collapse whitespace, cap.
  static String clipSnippet(String input) {
    var s = input.replaceAll(RegExp(r'<[^>]*>'), '');
    s = s.replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length <= kSearchSnippetCharCap) return s;
    return s.substring(0, kSearchSnippetCharCap).trim();
  }
}

String webSearchEmptyResultFragment(String query) =>
    SearchInjection.emptyResultFragment(query);

String webSearchResultFragment(String snippet) =>
    SearchInjection.resultFragment(snippet);
