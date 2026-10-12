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

import 'dart:async';
import 'dart:io';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart'
    show withoutCity96Ask;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';

/// Swipe, edit/delete, Needs redo, images, author note and chat lorebook for
/// the web chat. Each action delegates to the [ChatService] method the
/// desktop calls, then pushes `chat_updated`.
class ChatHistoryActions {
  ChatHistoryActions(
    this._chat,
    this._hub,
    this._notify, {
    File? Function(String name)? resolveSavedImage,
  }) : _resolveSavedImage = resolveSavedImage;

  final ChatService _chat;
  final StreamHub? _hub;
  final void Function() _notify;
  final File? Function(String name)? _resolveSavedImage;

  Map<String, dynamic> variants(int messageIndex) =>
      _chat.variantPickerPayload(messageIndex);

  Future<void> selectVariant(int messageIndex, int variantIndex) async {
    await _chat.selectVariant(messageIndex, variantIndex);
    _notify();
  }

  /// AI writes the user's next line into the composer (desktop wand parity).
  /// Tokens ride a dedicated `impersonate` WS event — never the `token`
  /// bubble stream.
  void impersonate(String prefix) {
    unawaited(
      _chat
          .impersonateUser(
            prefix: prefix,
            onToken: (acc) => _hub?.broadcastImpersonate(acc),
          )
          .whenComplete(() {
            _hub?.broadcastImpersonateDone();
            _notify();
          }),
    );
    _notify();
  }

  /// Director redo: re-evaluate a message's Needs deltas using the user's
  /// written [critique]. Awaited (it runs LLM evals) so the route can report the
  /// outcome; the new deltas + a pre-reprocess stash land in the message's
  /// metadata, which the next state fetch surfaces as chips. Reuses the existing
  /// ChatService flow — no parallel logic.
  /// [onlyNeeds] scopes the pass to those needs; empty re-evaluates all of
  /// them. Additive on the wire — an older PWA that omits it keeps the
  /// all-needs behaviour it has always had.
  Future<bool> reprocessNeeds(
    int index,
    String critique, {
    Set<String> onlyNeeds = const <String>{},
  }) async {
    final ok = await _chat.manualReprocessNeeds(
      index,
      critique,
      onlyNeeds: onlyNeeds,
    );
    _notify();
    return ok;
  }

  /// Manual Reprocess → Feelings: the Realism judges asked again about the
  /// line the last reply answers. The route tells a refusal (not on offer
  /// right now) apart from an answer that could not be read.
  Future<FeelingsRescore> reprocessFeelings(int index) async {
    final result = await _chat.reprocessFeelings(index);
    _notify();
    return result;
  }

  /// Restore a message's Needs deltas + live state from the pre-reprocess stash.
  Future<bool> revertNeedsReprocess(int index) async {
    final ok = await _chat.revertNeedsReprocess(index);
    _notify();
    return ok;
  }

  void swipe(int messageIndex, int direction, {String? critique}) {
    withoutCity96Ask(
      () => _chat.swipeMessage(messageIndex, direction, critique: critique),
    );
    _notify();
  }

  void edit(int index, String text) {
    _chat.editMessage(index, text);
    _notify();
  }

  void delete(int index) {
    _chat.deleteMessage(index);
    _notify();
  }

  /// Attach a generated image (saved under `KoboldManager/images/`) to the
  /// conversation as its own image message — the SAME path the desktop's
  /// /image command and the Image Studio's "Send to chat" use
  /// (ChatServiceImages.addGeneratedImageMessage), so it renders identically
  /// on both surfaces. Replaces the old markdown-append-to-last-message hack,
  /// which never rendered on desktop (relative URLs aren't matched by the
  /// markdown-image regex) and mutated an unrelated message.
  /// Resolve a parked /image prompt review from the web modal: the (possibly
  /// edited) prompt to generate with, or null to cancel. No-op when nothing
  /// is pending (e.g. the desktop dialog resolved it first).
  void resolveImageReview(String? prompt) {
    _chat.resolveImagePromptReview(prompt);
    _notify();
  }

  /// "Write it for me" on the phone's Image Studio: the prompt the writer
  /// makes for the chat that is open. Null when no image backend is set up.
  Future<String?> craftStudioPrompt(String subject, String instruction) =>
      _chat.craftStudioPrompt(subject, instruction);

  Future<bool> insertImage(String filename, {String prompt = ''}) async {
    final file = _resolveSavedImage?.call(filename.trim());
    if (file == null) return false;
    await _chat.addGeneratedImageMessage(file.path, prompt);
    _notify();
    return true;
  }

  void setAuthorNote(String note, {int? strength}) {
    _chat.setAuthorNote(note, strength: strength);
    _notify();
  }

  /// The chat-scoped lorebook as web editor rows (full-fidelity via `ext`).
  Map<String, dynamic> chatLorebookRows() => {
    'entries': lorebookEntriesToJson(_chat.chatLorebook),
  };

  /// Replace the chat-scoped lorebook from web editor rows. An empty/absent
  /// list clears it. Returns false when no session is active.
  Future<bool> setChatLorebook(dynamic rowsJson) async {
    if (_chat.currentSessionId == null) return false;
    final built = buildLorebookFromJson(rowsJson);
    _chat.chatLorebook.entries
      ..clear()
      ..addAll(built?.entries ?? const []);
    await _chat.commitChatLorebookEdit();
    _notify();
    return true;
  }

  /// Save per-chat theme overrides from the web UI.
  Future<bool> setThemeOverrides(Map<String, dynamic> json) async {
    if (_chat.currentSessionId == null) return false;
    _chat.sessionThemeOverrides = ChatThemeOverrides.fromJson(json);
    _notify();
    return true;
  }

  /// Mutation-free "would trigger next" preview for a composer draft —
  /// display names of idle entries the draft would wake up.
  List<String> lorePreview(String draft) => [
    for (final e in _chat.previewLoreTriggers(draft)) e.displayName,
  ];
}
