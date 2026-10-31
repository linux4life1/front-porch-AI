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
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';

// Debt: every hook below is state or behaviour another part of the chat
// service still owns. A hook goes when its owner becomes a door; the work
// package that retires it is named on each class.

/// The turn engine's flags and calls (WP10b, WP10c).
class EditTurnHooks {
  const EditTurnHooks({
    required this.isTurnBusy,
    required this.setPostGenerating,
    required this.yieldSettlingTurn,
    required this.clearPostGenAbortFlags,
    required this.abortIfBackendDown,
    required this.generate,
    required this.answerTrailingUserLine,
    required this.bumpMemoryEpoch,
    required this.mouthIsLocal,
    required this.setGenerating,
    required this.setPhase,
    required this.cancelRequested,
    required this.setCancelRequested,
    required this.mouthStream,
    required this.withWorkerLane,
    required this.mouthIdle,
  });

  /// A reply, its post-gen settle, an import or narration is running.
  final bool Function() isTurnBusy;

  /// The settling flag every mutation guard reads (`_isPostGenerating`).
  final void Function(bool on) setPostGenerating;

  /// Aborts in-flight post-gen evals so a regen can start; false when a
  /// stream, an import or a time-skip question still holds the turn.
  final Future<bool> Function() yieldSettlingTurn;
  final void Function() clearPostGenAbortFlags;

  /// Checked before anything is popped: true when the backend is down and
  /// the user was told so.
  final Future<bool> Function() abortIfBackendDown;

  /// One generation (`_generateResponse`).
  final Future<void> Function(
    GenerationMode mode, {
    bool directUserSend,
    CharacterCard? guestSpeaker,
    CharacterCard? forceSpeaker,
    String regenCritique,
  })
  generate;

  /// Try again on a trailing user line (`_generateFromTrailingUserTurn`).
  final Future<void> Function({
    String? webQuery,
    String? wikiQuery,
    CharacterCard? forceSpeaker,
  })
  answerTrailingUserLine;

  /// A regen invalidates Journal and Growth passes started on the old reply.
  final void Function() bumpMemoryEpoch;

  /// The chat model is KoboldCpp (word odds exist only there).
  final bool Function() mouthIsLocal;

  /// Impersonate streams on the narrow generating flag and its own phase.
  final void Function(bool on) setGenerating;
  final void Function(GenerationPhase phase) setPhase;
  final bool Function() cancelRequested;
  final void Function(bool on) setCancelRequested;

  /// The chat model's stream, after the worker lane yields the speech pin.
  final Stream<String> Function(GenerationParams params) mouthStream;

  /// Runs [work] on the worker lane when one is configured.
  final Future<bool> Function(Future<bool> Function() work) withWorkerLane;

  /// KoboldCpp's idle wait, or null when the mouth is not KoboldCpp.
  final Future<void>? Function() mouthIdle;
}

/// Realism-eval UI state and the realism restores other parts hold (WP7,
/// WP9a). The last four are bodies a hygiene test pins to their part file.
class EditRealismHooks {
  const EditRealismHooks({
    required this.realismActiveThisMode,
    required this.evalCancelled,
    required this.setEvalCancelled,
    required this.setEvaluatingRealism,
    required this.clearEvalStream,
    required this.onEvalChunk,
    required this.stopEvalChunkTimer,
    required this.restoreForSpeaker,
    required this.keepingLiveSpeaker,
    required this.rewindToLastAcceptedReply,
    required this.restoreScoredRegisters,
    required this.applyMoodDecay,
    required this.plantTierCrossing,
    required this.revertRegenBaseline,
    required this.replayRegenJudges,
    required this.needsBeforeDelete,
    required this.rewindPocketsForDelete,
  });

  /// The Realism Engine scores the user in this chat mode.
  final bool Function() realismActiveThisMode;

  /// The user cancelled the Realism eval (`_realismEvalCancelled`).
  final bool Function() evalCancelled;
  final void Function(bool on) setEvalCancelled;
  final void Function(bool on) setEvaluatingRealism;

  /// Empties the overlay's streamed eval text.
  final void Function() clearEvalStream;

  /// Appends a judge chunk to the overlay text, one rebuild per 150 ms.
  final void Function(String chunk) onEvalChunk;

  /// Cancels the pending overlay rebuild.
  final void Function() stopEvalChunkTimer;

  /// The group-aware realism restore from a message's snapshot.
  final void Function(ChatMessage msg, {bool restoreClock}) restoreForSpeaker;

  /// Runs [body] and puts the mid-turn speaker's scalars back after it.
  final void Function(void Function() body) keepingLiveSpeaker;

  /// 1:1 stamp-less rewind of the scored registers to the last reply.
  final bool Function() rewindToLastAcceptedReply;
  final void Function(Map<String, dynamic> stamp) restoreScoredRegisters;
  final void Function() applyMoodDecay;

  /// Plants an Our Story card for a tier the score crossed.
  final void Function(TierCrossing crossing, {required int citeLength})
  plantTierCrossing;

  /// Regen's rewind to the pre-turn baseline (chat_service_regen_revert:
  /// it reads the chat's stored Needs switch, needs_gate_ratchet_test).
  /// False when the baseline is unreadable and nothing may be generated.
  final bool Function({
    required ChatMessage lastMsg,
    required CharacterCard? regenGuest,
    required CharacterCard? regenSpeakerCard,
    required String regenSpeakerSid,
  })
  revertRegenBaseline;

  /// 1:1 regen's decay and judge replay (chat_service_reprocess,
  /// trust_repair_regen_latch_test). False when the user cancelled it; the
  /// popped reply is then already back with its accepted state.
  final Future<bool> Function(ChatMessage lastMsg) replayRegenJudges;

  /// Delete's Needs baseline for the deleted speaker, empty when no refund
  /// applies (chat_service_message_ops, needs_gate_ratchet_test).
  final Map<String, int> Function(String? deletedSid) needsBeforeDelete;

  /// Delete's Pockets rewind (chat_service_message_ops,
  /// catastrophe_clear_on_cancel_test).
  final void Function(ChatMessage deleted, {required bool wasTail})
  rewindPocketsForDelete;
}

/// Scene Guests, the group speaker pick and the opening greeting (WP6).
class EditCastHooks {
  const EditCastHooks({
    required this.guestBusy,
    required this.isGuestAuthored,
    required this.guestFor,
    required this.setStatus,
    required this.guestChimeIns,
    required this.pickPresentSpeaker,
    required this.greetingIndex,
    required this.setGreetingIndex,
    required this.greetingOwner,
    required this.firstMessage,
    required this.invalidateGreetingEval,
    required this.stampGreetingIndex,
    required this.isOpeningGreetingChat,
    required this.seedGroupGreeting,
    required this.seedGreeting,
  });

  /// A Scene Guest turn is running.
  final bool Function() guestBusy;

  /// [m] was written by a Scene Guest, present or gone.
  final bool Function(ChatMessage m) isGuestAuthored;

  /// The present guest who wrote [m], or null.
  final CharacterCard? Function(ChatMessage m) guestFor;

  /// The chat's one-line status notice.
  final void Function(String? text, {bool isError}) setStatus;

  /// Re-runs the guest chime gate against the new host reply.
  final Future<void> Function({required String userText}) guestChimeIns;

  /// A present group member, for a group impersonate nobody has answered.
  final CharacterCard Function() pickPresentSpeaker;

  /// The opening greet on screen.
  final int Function() greetingIndex;
  final void Function(int index) setGreetingIndex;

  /// Who owns the opening bubble (null for a custom group greeting).
  final CharacterCard? Function() greetingOwner;

  /// A card greet, macro-resolved as the opening bubble shows it.
  final String Function(CharacterCard card, {String? greetingText})
  firstMessage;

  /// Drops a stale greeting eval before the opening changes.
  final Future<void> Function() invalidateGreetingEval;
  final void Function(int index) stampGreetingIndex;

  /// The chat holds only its opening.
  final bool Function() isOpeningGreetingChat;

  /// Re-seeds a custom group greeting's Realism and Needs.
  final Future<void> Function(int index) seedGroupGreeting;

  /// Re-seeds a card greet's Realism and Needs.
  final Future<void> Function({required CharacterCard card, required int index})
  seedGreeting;
}

/// The prompt pieces impersonate shares with the reply path (WP10a).
class ImpersonatePromptHooks {
  const ImpersonatePromptHooks({
    required this.groupBasePrompt,
    required this.oneToOneBase,
    required this.amendmentsAllowed,
    required this.sessionGenSettings,
    required this.userPersonaBlock,
    required this.chatHistory,
    required this.authorNote,
    required this.authorNoteBlock,
    required this.macroContext,
    required this.countTokens,
    required this.historyWithin,
    required this.overflowHistory,
  });

  final String Function() groupBasePrompt;
  final String Function(CharacterCard card) oneToOneBase;

  /// Global system-prompt and post-history additions may be applied.
  final bool Function() amendmentsAllowed;
  final ChatGenerationSettings Function() sessionGenSettings;
  final Future<String> Function(String userName) userPersonaBlock;

  /// The whole transcript, unbudgeted.
  final String Function() chatHistory;
  final String Function() authorNote;
  final String Function() authorNoteBlock;
  final MacroContext Function(CharacterCard speaking, {String? scenario})
  macroContext;
  final Future<int> Function(String text) countTokens;

  /// The transcript that fits [budget] tokens, with depth lore placed.
  final Future<String> Function(int budget, List<LoreDepthEntry> depthLore)
  historyWithin;

  /// The overflow floor: last user line and everything after it.
  final String Function() overflowHistory;
}
