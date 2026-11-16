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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools/chat_tools_context.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// The plain toggles: engine, needs, one-shot, chaos, passage of time,
/// Director, wiki base. Each writes the same setting the
/// desktop row writes and pushes to the live chat where the desktop does.
class ChatToolsSwitches {
  ChatToolsSwitches(this._ctx);

  final ChatToolsContext _ctx;
  ChatService get _chat => _ctx.chat;
  StorageService get _storage => _ctx.storage;
  void _notify() => _ctx.notify();

  Future<void> setRealismEnabled(bool v) async {
    await _chat.setRealismEnabled(v);
    _notify();
  }

  /// Live in-chat Needs Simulation toggle. Delegates to the same
  /// [ChatService.setNeedsSimEnabled] the desktop sidebar calls, so clock-wear
  /// / scene-impact behavior and 1:1↔group parity are inherited.
  Future<void> setNeedsEnabled(bool v) async {
    await _chat.setNeedsSimEnabled(v);
    _notify();
  }

  /// Live in-chat Pockets & Wardrobe toggle for THIS chat
  /// (docs/design/pockets-wardrobe-chat-toggle.md). The PWA shows the same
  /// freeze confirmation the desktop dialog shows before calling with
  /// false; the setter retains the record and stops every pockets model
  /// call, so no catch-up happens either side.
  Future<void> setPocketsEnabled(bool v) async {
    await _chat.setPocketsEnabled(v);
    _notify();
  }

  /// A group member's own Pockets switch in this chat — the web twin of
  /// the sidebar member-card line, one member at a time. False when [id]
  /// is not a member, so the route can reject a bad id.
  Future<bool> setMemberPockets(String id, bool v) async {
    for (final c in _chat.groupCharacters) {
      if (groupMemberStoreId(c) != id) continue;
      await _chat.setMemberPocketsEnabled(id, v);
      _notify();
      return true;
    }
    return false;
  }

  /// Legacy bool One-Shot toggle — kept so an older PWA bundle's toggle keeps
  /// working (additive contract). An explicit toggle maps to On/Off, never
  /// Auto, the same rule the storage shim applies.
  Future<void> setOneShotEval(bool v) async {
    await _storage.realismSettings.setRealismOneShotEval(v);
    _notify();
  }

  /// Tri-state One-Shot mode (Auto / On / Off) — the same
  /// [StorageService.oneShotMode] the desktop realism sidebar drives. Auto
  /// resolves per turn against the live backend (resolveOneShotMode); the web
  /// only stores the choice — never branches — so one-shot/multi-call parity
  /// is inherited exactly as it was for the bool.
  Future<void> setOneShotMode(OneShotMode v) async {
    await _storage.realismSettings.setOneShotMode(v);
    _notify();
  }

  Future<void> setChaosEnabled(bool v) async {
    await _chat.setChaosModeEnabled(v);
    _notify();
  }

  Future<void> setChaosNsfw(bool v) async {
    await _chat.setChaosNsfwEnabled(v);
    _notify();
  }

  /// This chat's own Afterglow switch (1:1), or every member's (group; an
  /// older phone's switch, which had one for the chat).
  Future<void> setAfterglow(bool v) async {
    await _chat.setAfterglowEnabled(v);
    _notify();
  }

  /// A group member's own switches in this chat, the web twin of the
  /// sidebar's Character State header, Needs line and Afterglow line, one
  /// member at a time. False when [id] is not a member, so the route can
  /// reject a bad id.
  Future<bool> setMemberAfterglow(String id, bool v) =>
      _forMember(id, (m) => _chat.setMemberAfterglowSwitch(m, v));

  Future<bool> setMemberRealism(String id, bool v) =>
      _forMember(id, (m) => _chat.setMemberRealismEnabled(m, v));

  Future<bool> setMemberNeeds(String id, bool v) =>
      _forMember(id, (m) => _chat.setMemberNeedsEnabled(m, v));

  // PR 5b: the member's own Chaos Mode and its 18+ events toggle.
  Future<bool> setMemberChaos(String id, bool v) =>
      _forMember(id, (m) => _chat.setMemberChaosEnabled(m, v));

  Future<bool> setMemberChaosNsfw(String id, bool v) =>
      _forMember(id, (m) => _chat.setMemberChaosNsfw(m, v));

  Future<bool> _forMember(
    String id,
    Future<void> Function(String) write,
  ) async {
    for (final c in _chat.groupCharacters) {
      if (groupMemberStoreId(c) != id || c.isLite) continue;
      await write(_chat.characterIdFor(c));
      _notify();
      return true;
    }
    return false;
  }

  /// A group member's Recovery block. False when [id] is not a member or
  /// [fields] is not a Recovery block, so a bare call resets nothing.
  Future<bool> setMemberRecovery(String id, Object? fields) async {
    if (fields is! Map) return false;
    for (final c in _chat.groupCharacters) {
      if (groupMemberStoreId(c) != id) continue;
      c.frontPorchExtensions =
          (c.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            recovery: RecoveryProfile.fromFields(fields),
          );
      await _chat.persistGroupMemberExtensions(memberId: id);
      _notify();
      return true;
    }
    return false;
  }

  Future<void> setPassageOfTime(bool v) async {
    await _chat.setPassageOfTimeEnabled(v);
    _notify();
  }

  /// Director Mode from the web's switch: the same narrated step out (or
  /// back in) as `/director`, with its UNDO. Group-only; the web gates it.
  Future<void> setDirectorMode(bool v) async {
    if (v != _chat.observerMode) {
      await _chat.sendMessage(v ? '/director' : '/director off');
    }
    _notify();
  }

  Future<void> setWikiBaseUrl(String url) async {
    await _chat.setWikiBaseUrl(url);
    _notify();
  }
}
