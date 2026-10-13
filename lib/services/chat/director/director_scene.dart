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

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Session-blob keys for the director's standing directions. Additive: old
/// app versions ignore them.
const String kDirectorGoalSessionKey = 'directorGoal';
const String kDirectorWhispersSessionKey = 'directorWhispers';

/// Longest goal or whisper kept, so one paste can't flood every prompt.
const int kDirectorDirectionMaxChars = 400;

/// The director's standing directions for one chat: a pinned scene goal the
/// whole cast steers toward, and private whispers only one member sees.
///
/// They are injected only while the user directs. Stepping back in hides
/// them; it does not erase them, so stepping out again finds them there.
class DirectorScene {
  String _goal = '';
  final Map<String, String> _whispers = {};

  String get goal => _goal;

  /// Whispers by member id (the speaker id generation uses).
  Map<String, String> get whispers => Map.unmodifiable(_whispers);

  bool get isEmpty => _goal.isEmpty && _whispers.isEmpty;

  static String _clip(String text) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length <= kDirectorDirectionMaxChars
        ? t
        : '${t.substring(0, kDirectorDirectionMaxChars)}…';
  }

  /// Sets the goal; empty text clears it.
  void setGoal(String text) => _goal = _clip(text);

  /// Sets [memberId]'s whisper; empty text clears it.
  void setWhisper(String memberId, String text) {
    final t = _clip(text);
    if (t.isEmpty) {
      _whispers.remove(memberId);
    } else {
      _whispers[memberId] = t;
    }
  }

  /// The hidden author-note lines for [speakerId]'s turn: the goal for
  /// everyone, the whisper for this speaker only.
  String promptBlock({required String speakerId, required String speakerName}) {
    final b = StringBuffer();
    if (_goal.isNotEmpty) {
      b.writeln(
        '[Scene goal from the director (hidden — do NOT quote it): $_goal. '
        'Let the scene move toward it naturally over the coming turns; do '
        'not jump straight to it.]',
      );
    }
    final whisper = _whispers[speakerId];
    if (whisper != null) {
      b.writeln(
        '[Private direction for $speakerName only (hidden — the other '
        'characters do not know this; do NOT quote it): $whisper]',
      );
    }
    return b.toString();
  }

  /// The fragment the session blob saves; empty when there is nothing.
  Map<String, dynamic> toJsonFragment() => {
    if (_goal.isNotEmpty) kDirectorGoalSessionKey: _goal,
    if (_whispers.isNotEmpty) kDirectorWhispersSessionKey: whispers,
  };

  /// Replaces everything with what [json] (a session blob) saved. Null or a
  /// blob without the keys means a chat with no directions.
  void hydrate(String? json) {
    _goal = '';
    _whispers.clear();
    if (json == null || json.isEmpty || json == '{}') return;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return;
      final goal = decoded[kDirectorGoalSessionKey];
      if (goal is String) _goal = _clip(goal);
      final whispers = decoded[kDirectorWhispersSessionKey];
      if (whispers is Map) {
        for (final e in whispers.entries) {
          if (e.value is String) setWhisper(e.key.toString(), e.value);
        }
      }
    } catch (e) {
      debugPrint('[Director] unreadable directions in session blob: $e');
    }
  }
}
