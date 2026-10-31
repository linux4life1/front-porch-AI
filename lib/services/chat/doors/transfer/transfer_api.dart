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

/// Bridge: the import and export names a chat service value has always had,
/// each forwarding to its door ([ChatService.chatImporter] or
/// [ChatService.chatPackager]). The shell exports this library, so callers
/// keep their imports. Extension names are the retired parts' names, so
/// doc links to them still resolve.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat_service.dart';

extension ChatServiceSillyTavern on ChatService {
  /// Export current chat as **SillyTavern JSONL** (dialogue only).
  String? exportToSillyTavern() => chatPackager.exportToSillyTavern();
}

extension ChatServiceChatPackage on ChatService {
  /// Export current chat as a `.fpchat` zip (full timeline). Null if empty.
  Future<Uint8List?> exportToFpchat() => chatPackager.exportToFpchat();
}

extension ChatServiceChatPackageImport on ChatService {
  /// Import a `.fpchat` zip or legacy ST-ish JSON bytes into a **new** session.
  Future<({bool fullRestore, String? warning})> importChatPackage(
    Uint8List bytes, {
    Future<bool> Function(String packageName, String activeName)?
    onCharacterMismatch,
  }) => chatImporter.importChatPackage(
    bytes,
    onCharacterMismatch: onCharacterMismatch,
  );

  /// Test hook: import awaits this before mutating so a Send can race it.
  @visibleForTesting
  Completer<void>? get testImportHold => chatImporter.testImportHold;
  @visibleForTesting
  set testImportHold(Completer<void>? hold) =>
      chatImporter.testImportHold = hold;

  /// Test hook: live `realism_state` capture key set for stamp-contract guards.
  @visibleForTesting
  Map<String, dynamic> debugCaptureRealismStateForFpchat() =>
      chatImporter.debugCaptureRealismState();
}

extension ChatServiceTransferTestHooks on ChatService {
  /// Register a 1:1 Scene Guest without an entrance turn (import + tests).
  @visibleForTesting
  Future<void> debugEnterSceneGuestSilent(CharacterCard guest) =>
      chatImporter.debugEnterSceneGuestSilent(guest);

  /// Seed a transcript so [exportToFpchat] has something to pack.
  @visibleForTesting
  void debugSeedTranscriptForFpchat(List<ChatMessage> msgs) =>
      chatPackager.debugSeedTranscript(msgs);
}

extension ChatServiceEnhanceChats on ChatService {
  /// Claims the shared chat for one `.porch` job; false while another job
  /// holds it. Every true must be paired with [endMovingChats].
  bool tryBeginMovingChats() => chatPackager.tryBeginMovingChats();

  void endMovingChats() => chatPackager.endMovingChats();

  /// Every 1:1 chat of [card] as an `.fpchat` package, newest first.
  Future<List<Uint8List>> exportChatPackagesOf(CharacterCard card) =>
      chatPackager.exportChatPackagesOf(card);

  /// Restores [packages] onto [card] as new chats; returns how many came
  /// back with their full state.
  Future<int> importChatPackagesOnto(
    CharacterCard card,
    List<Uint8List> packages, {
    void Function(int done, int total)? onProgress,
  }) => chatPackager.importChatPackagesOnto(
    card,
    packages,
    onProgress: onProgress,
  );

  /// Copies every chat of [from] onto [to]; returns how many were copied.
  Future<int> copyChatsForEnhance({
    required CharacterCard from,
    required CharacterCard to,
    void Function(int done, int total)? onProgress,
  }) => chatPackager.copyChatsForEnhance(
    from: from,
    to: to,
    onProgress: onProgress,
  );
}
