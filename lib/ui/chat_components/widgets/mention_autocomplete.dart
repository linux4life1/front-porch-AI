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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The "@" cast autocomplete shown above the chat input — the cast-name twin
/// of the "type /" command helper in chat_page (same panel visuals, same
/// fill-the-input behavior). Appears while the token at the cursor is "@…"
/// and the scene has someone addressable: host + Scene Guests in a 1:1 (only
/// when guests are present), every member in a group (not in observer mode —
/// there the composer writes director notes, not addressed turns). Tapping a
/// row splices "@Full Name " over the token; `sendMessage`'s direct-address
/// router then makes that character answer the turn.
class MentionAutocomplete extends StatelessWidget {
  const MentionAutocomplete({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// The in-progress "@" token ending at [cursor] in [text], or null when the
  /// cursor isn't inside one. Mirrors the send-time matcher's boundary rule:
  /// the @ must not follow a word char/dot/hyphen/plus (so typing an email
  /// never opens the popup). The prefix charset is unicode letters/digits
  /// (accented names filter too) and stops at a space — after "@Mara " the
  /// token is complete; multi-word names are picked from the list, not typed
  /// out. Kept in lock-step with the web composer's twin. Static + pure for
  /// unit tests.
  static MentionQuery? activeMentionQuery(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    final head = text.substring(0, cursor);
    final m = RegExp(
      r'(?:^|[^\w.+\-])@([\p{L}\p{N}_]*)$',
      unicode: true,
    ).firstMatch(head);
    if (m == null) return null;
    final prefix = m.group(1)!;
    return MentionQuery(start: cursor - prefix.length - 1, prefix: prefix);
  }

  /// Case-insensitive candidate filter: the full name or ANY whitespace token
  /// of it starts with [prefix] ("@van" finds "Mara Vance"). Empty prefix
  /// matches everyone. Static + pure for unit tests.
  static bool nameMatches(String name, String prefix) {
    if (prefix.isEmpty) return true;
    final p = prefix.toLowerCase();
    final n = name.trim().toLowerCase();
    if (n.startsWith(p)) return true;
    return n.split(RegExp(r'\s+')).any((t) => t.startsWith(p));
  }

  @override
  Widget build(BuildContext context) {
    // Deliberately NOT watching ChatService: this panel is hidden almost
    // always, and a subscription would rebuild it on every streamed token.
    // The ValueListenableBuilder re-runs per keystroke/caret move, which is
    // the refresh cadence that matters; a cast change lands on the next one.
    final chat = Provider.of<ChatService>(context, listen: false);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        // No popup during IME composition or over a range selection — both
        // leave the caret/token ambiguous.
        if (value.composing.isValid) return const SizedBox.shrink();
        final sel = value.selection;
        if (sel.isValid && !sel.isCollapsed) return const SizedBox.shrink();
        final cursor = sel.isValid ? sel.extentOffset : value.text.length;
        final q = activeMentionQuery(value.text, cursor);
        if (q == null) return const SizedBox.shrink();
        // Who can be addressed right now (matches the send-time router's
        // scope). Built only while an "@" token is active, and read without
        // subscribing (see the Provider.of above) — keep it that way.
        final entries = <(String, String)>[];
        if (chat.isGroupMode) {
          if (chat.observerMode) return const SizedBox.shrink();
          for (final c in chat.groupCharacters) {
            entries.add((c.name, 'Group member — answers this turn'));
          }
        } else if (chat.sceneGuestCards.isNotEmpty) {
          final host = chat.activeCharacter;
          if (host != null) {
            entries.add((host.name, 'Main character — keeps the turn'));
          }
          for (final g in chat.sceneGuestCards) {
            entries.add((g.name, 'Scene Guest — answers in their own reply'));
          }
        }
        final matches = entries
            .where((e) => nameMatches(e.$1, q.prefix))
            .toList();
        if (matches.isEmpty) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: matches.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              thickness: 1,
              color: AppColors.borderOf(context).withValues(alpha: 0.4),
            ),
            itemBuilder: (context, i) {
              final (name, role) = matches[i];
              return InkWell(
                onTap: () => _insert(value, q, name),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 200,
                        child: Text(
                          '@$name',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: AppColors.porchAmberOf(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          role,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Splice "@[name] " over the in-progress token and put the caret after it.
  void _insert(TextEditingValue value, MentionQuery q, String name) {
    final sel = value.selection;
    if (sel.isValid && !sel.isCollapsed) return; // popup was hidden anyway
    final cursor = sel.isValid ? sel.extentOffset : value.text.length;
    final inserted = '@$name ';
    final text =
        value.text.substring(0, q.start) +
        inserted +
        value.text.substring(cursor);
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: q.start + inserted.length),
    );
    focusNode.requestFocus();
  }
}

/// An in-progress "@" token: [start] is the index of the @ itself, [prefix]
/// the characters typed after it so far.
class MentionQuery {
  const MentionQuery({required this.start, required this.prefix});
  final int start;
  final String prefix;
}
