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

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat_service.dart';

/// The prompt assembler's old public names (bodies in [ContextBudget],
/// [PromptSource] and [PromptBlocks]). The Context Viewer's class
/// forwarders on the shell (lastPromptBudget, lastPromptSections,
/// promptBudgetSource, promptBudgetAssembledAt, promptDroppedMessages,
/// estimateContextBudgetNow, contextSize) stay there because test doubles
/// override them.
extension ChatServicePrompts on ChatService {
  /// The prompt record of the reply at [index], or null when none was kept.
  ContextViewerSnapshot? replyContextSnapshot(int index) =>
      promptAssembler.budget.replyContextSnapshot(index);

  /// The character key whose new 1:1 chat is waiting on the prompt picker,
  /// or null when nothing is pending (see [PromptSource]).
  String? get promptPickerPendingFor =>
      promptAssembler.source.promptPickerPendingFor;

  /// The picker's answer (see [PromptSource.applyPromptSourceChoice]).
  Future<void> applyPromptSourceChoice({
    String? preset,
    bool remember = false,
    bool askEveryChat = false,
  }) => promptAssembler.source.applyPromptSourceChoice(
    preset: preset,
    remember: remember,
    askEveryChat: askEveryChat,
  );

  /// Chat Settings' System prompt row from outside the picker (the web
  /// app's per-chat drawer); 1:1 only.
  Future<bool> setPromptSource({String? source, bool? amendments}) =>
      promptAssembler.source.setPromptSource(
        source: source,
        amendments: amendments,
      );

  /// The per-chat prompt source as the web app shows it.
  Map<String, Object?>? get promptSourceJson =>
      promptAssembler.source.promptSourceJson;

  /// Writes the Author's Note (and its strength), saves and repaints.
  void setAuthorNote(String note, {int? strength}) =>
      promptAssembler.blocks.setAuthorNote(note, strength: strength);

  /// Names of lore entries dropped by the token budget on the last
  /// generation, plus the meter numbers the sidebar shows.
  List<String> get lastLoreOverflow => promptAssembler.lastLoreOverflow;
  int get lastLoreTokens => promptAssembler.lastLoreTokens;
  int get lastLoreBudget => promptAssembler.lastLoreBudget;
}
