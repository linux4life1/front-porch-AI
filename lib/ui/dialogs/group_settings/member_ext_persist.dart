// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Writes a group member's edited [CharacterCard.frontPorchExtensions] to disk.
///
/// The Group Settings member cards (needs baselines, Pace, per-need on/off,
/// "enjoys low hygiene", the per-member Director/Verifier settings) mutate the
/// live card ext in memory and stash a copy in the group's
/// `defaultMemberRealismState` blob — which nothing reads back for an existing
/// group. The dialog's Save writes only the `groups` row, so those edits used
/// to be gone on the next launch while the runtime kept reading
/// `frontPorchExtensions`: settings that silently un-set themselves.
///
/// [ChatService.persistGroupMemberExtensions] is the ONE call that serializes a
/// member's whole ext to its avatar PNG and its `group_members` row. Hand-rolling
/// the PNG/DB write here would be a second copy of it, free to drift.
///
/// Writes are debounced per member because they re-encode the avatar PNG and
/// the callers include sliders. Only one write per member is ever in flight
/// (two concurrent saves would race on the same PNG).
class GroupMemberExtPersister {
  GroupMemberExtPersister(
    this.chatService, {
    this.delay = const Duration(milliseconds: 700),
  });

  final ChatService chatService;
  final Duration delay;

  final Map<String, Timer> _timers = {};
  final Map<String, CharacterCard> _queued = {};

  /// Queue [char]'s ext for persistence, restarting its debounce window.
  void schedule(CharacterCard char) {
    final id = groupMemberStoreId(char);
    _queued[id] = char;
    _timers[id]?.cancel();
    _timers[id] = Timer(delay, () => flushMember(id));
  }

  /// Write one member's queued ext now. Safe to call with nothing queued.
  Future<void> flushMember(String id) async {
    _timers.remove(id)?.cancel();
    final char = _queued.remove(id);
    if (char == null) return;
    try {
      await chatService.persistGroupMemberExtensions(memberId: id);
    } catch (e) {
      debugPrint('[GroupSettings] Failed to persist member ext for $id: $e');
    }
  }

  /// Write everything still queued — closing the dialog must not drop an edit.
  Future<void> flushAll() async {
    for (final id in _timers.keys.toList()) {
      await flushMember(id);
    }
  }

  void dispose() {
    // Fire-and-forget: the dialog is going away, the service is not.
    flushAll();
  }
}
