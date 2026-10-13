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

import 'package:front_porch_ai/services/chat/scene_guest_director.dart';

/// The auto-chat run: how many turns are left before it pauses itself.
/// Armed when auto-chat starts; a limit of 0 runs until it is stopped.
class AutoChatBudget {
  int _remaining = 0;
  bool _limited = false;

  /// Turns left in this run, or null when the run has no limit.
  int? get remaining => _limited ? _remaining : null;

  void arm(int limit) {
    _limited = limit > 0;
    _remaining = _limited ? limit : 0;
  }

  /// Spends one finished turn. True when that was the run's last turn.
  bool spend() {
    if (!_limited) return false;
    _remaining = (_remaining - 1).clamp(0, 1 << 30);
    return _remaining == 0;
  }
}

final RegExp _quoted = RegExp(r'"([^"]+)"|“([^”]+)”');
final RegExp _sentenceEnd = RegExp(r'(?<=[.!?…])\s+');

/// Whether [reply] speaks to [userName] directly, in dialogue: "Sam, are you
/// there?", "Where did you go, Sam?" or "@Sam". A mention ("I miss Sam") is
/// not an address. With no quoted dialogue the whole reply is read.
bool replyAddressesUser(String reply, String userName) {
  if (userName.trim().isEmpty || reply.trim().isEmpty) return false;
  final spoken = [
    for (final m in _quoted.allMatches(reply)) (m.group(1) ?? m.group(2))!,
  ];
  for (final segment in spoken.isEmpty ? [reply] : spoken) {
    for (final sentence in segment.trim().split(_sentenceEnd)) {
      final s = sentence.trim();
      if (s.isEmpty) continue;
      if (SceneGuestDirector.isVocativeAddress(userName, s)) return true;
    }
  }
  return false;
}
