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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edits_door.dart';
import 'package:front_porch_ai/services/chat_service.dart';

export 'package:front_porch_ai/services/chat/doors/edits/reprocessor.dart'
    show FeelingsRescore;

/// Edit, delete and the session clears (bodies in [MessageEditor]).
extension ChatServiceMessageOps on ChatService {
  /// Navigate swipes on a specific message. direction: -1 = left, +1 = right.
  /// If swiping right past the last swipe on the last bot message, regenerates.
  Future<void> swipeMessage(
    int messageIndex,
    int direction, {
    String? critique,
  }) => editsDoor.swipes.swipeMessage(
    messageIndex,
    direction,
    critique: critique,
  );

  /// Reload the current session from the database without clearing messages
  /// first (after cloud sync or a database migration).
  Future<void> reloadCurrentSession() =>
      editsDoor.editor.reloadCurrentSession();

  void clearChat() => editsDoor.editor.clearChat();

  /// Delete a chat and its messages; see [MessageEditor.deleteSession].
  Future<void> deleteSession(
    String sessionId, {
    bool startReplacement = true,
  }) => editsDoor.editor.deleteSession(
    sessionId,
    startReplacement: startReplacement,
  );

  Future<void> deleteMessage(int index) =>
      editsDoor.editor.deleteMessage(index);
}

/// Regenerate (bodies in [RegenController]).
extension ChatServiceReprocess on ChatService {
  /// Regenerate the host's reply buried under Scene Guest chime-ins; see
  /// [RegenController.regenerateMainCharacter].
  Future<void> regenerateMainCharacter({
    String? critique,
    String? webQuery,
    String? wikiQuery,
  }) => editsDoor.regen.regenerateMainCharacter(
    critique: critique,
    webQuery: webQuery,
    wikiQuery: wikiQuery,
  );

  Future<void> regenerateLastMessage({
    String? critique,
    String? webQuery,
    String? wikiQuery,
  }) => editsDoor.regen.regenerateLastMessage(
    critique: critique,
    webQuery: webQuery,
    wikiQuery: wikiQuery,
  );
}

/// Who a Reprocess would run as (bodies in [ReprocessTargets]).
extension ChatServiceNeedsReprocessTarget on ChatService {
  ({String speaker, List<String> enabled, CharacterCard? card})?
  reprocessNeedsTargetFor(int index) =>
      editsDoor.reprocess.targets.reprocessNeedsTargetFor(index);

  String? reprocessFeelingsTargetFor(int index) =>
      editsDoor.reprocess.targets.reprocessFeelingsTargetFor(index);
}

/// Manual Reprocess → Feelings (body in [Reprocessor]).
extension ChatServiceFeelingsRescore on ChatService {
  Future<FeelingsRescore> reprocessFeelings(int index) =>
      editsDoor.reprocess.reprocessFeelings(index);
}

/// Manual Reprocess → Needs (body in [NeedsReprocess]).
extension ChatServiceNeedsReprocess on ChatService {
  /// Re-evaluate a message's needs deltas under a user critique; see
  /// [NeedsReprocess.manualReprocessNeeds] for [onlyNeeds] scoping.
  Future<bool> manualReprocessNeeds(
    int index,
    String critique, {
    Set<String> onlyNeeds = const <String>{},
  }) => editsDoor.reprocess.manualReprocessNeeds(
    index,
    critique,
    onlyNeeds: onlyNeeds,
  );

  /// Revert a prior manual reprocess on the given message.
  Future<bool> revertNeedsReprocess(int index) =>
      editsDoor.reprocess.revertNeedsReprocess(index);
}

/// The greet and swipe picker (bodies in [SwipeVariants]).
extension ChatServiceVariants on ChatService {
  /// The card whose greets the opening picker cycles.
  List<String> get openingAllGreetings => editsDoor.swipes.openingAllGreetings;

  bool isSelectableGreeting(int messageIndex) =>
      editsDoor.swipes.isSelectableGreeting(messageIndex);

  List<VariantOption> variantsForMessage(int messageIndex) =>
      editsDoor.swipes.variantsForMessage(messageIndex);

  Map<String, dynamic> variantPickerPayload(int messageIndex) =>
      editsDoor.swipes.variantPickerPayload(messageIndex);

  Future<void> selectGreeting(int index) =>
      editsDoor.swipes.selectGreeting(index);

  Future<void> selectSwipe(int messageIndex, int swipeIndex) =>
      editsDoor.swipes.selectSwipe(messageIndex, swipeIndex);

  Future<void> selectVariant(int messageIndex, int variantIndex) =>
      editsDoor.swipes.selectVariant(messageIndex, variantIndex);
}

/// Token alternatives (bodies in [TokenAlts]).
extension ChatServiceTokenAlts on ChatService {
  List<TokenAlternative> tokenAlternativesAt(int index) =>
      editsDoor.tokenAlts.tokenAlternativesAt(index);

  String? tokenAltsPickRefusal(int index) =>
      editsDoor.tokenAlts.tokenAltsPickRefusal(index);

  Future<bool> rewriteFromAlternative(
    int index,
    TokenAlternative at,
    String pick,
  ) => editsDoor.tokenAlts.rewriteFromAlternative(index, at, pick);

  Map<String, dynamic> tokenAlternativesJson(int index) =>
      editsDoor.tokenAlts.tokenAlternativesJson(index);

  ({TokenAlternative? at, String? refusal}) tokenAltPick(
    int index,
    int place,
    String word,
  ) => editsDoor.tokenAlts.tokenAltPick(index, place, word);
}

/// Impersonate (body in [Impersonator]).
extension ChatServiceImpersonate on ChatService {
  Future<void> impersonateUser({
    String prefix = '',
    required Function(String accumulated) onToken,
  }) =>
      editsDoor.impersonator.impersonateUser(prefix: prefix, onToken: onToken);
}
