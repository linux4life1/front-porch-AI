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

/// Index of the latest user message, or the last message when there is no
/// user line. Overflow history must start here: a Scene Guest chime-in
/// used to keep only `_messages.last` (the host's reaction) and the user
/// question vanished, so the guest answered an older line (Discord 2026-08-15).
int overflowHistoryStart(List<ChatMessage> messages) {
  if (messages.isEmpty) return 0;
  for (var i = messages.length - 1; i >= 0; i--) {
    if (messages[i].isUser) return i;
  }
  return messages.length - 1;
}

/// Most messages a reply prompt moves after the state zone as the latest
/// beat. A group can run several replies past the user's last line; past
/// this many, only the newest stay together so the moved block (re-read
/// in full every turn) stays small.
const int kLatestTurnMaxMessages = 4;

/// Where the latest beat starts: the latest user line and everything after
/// it ([overflowHistoryStart]), capped to the newest
/// [kLatestTurnMaxMessages]. A reply prompt renders these last, right
/// before the speaker's name, so a small local model answers THIS turn
/// instead of the long replies and state notes it read on the way down.
int latestTurnStart(List<ChatMessage> messages) {
  final start = overflowHistoryStart(messages);
  final floor = messages.length - kLatestTurnMaxMessages;
  return start > floor ? start : floor;
}

/// Clip + sanitize a cited line so it cannot break out of the guest-turn
/// `[...]` wrapper or balloon the fixed prompt.
String clipGuestCite(String text, {int max = 400}) {
  var t = text
      .replaceAll('[', '(')
      .replaceAll(']', ')')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.length > max) t = '${t.substring(0, max)}…';
  return t;
}

/// The SCENE GUEST TURN author-note. Identity switch plus an explicit pin
/// of the latest user line so DeepSeek-class models cannot treat an older
/// "Magus, tell me about the spell" as the question they are answering.
String buildGuestTurnNote({
  required String guestName,
  required String hostName,
  required String userName,
  required String latestUserText,
  String latestHostText = '',
}) {
  final user = clipGuestCite(latestUserText);
  final host = clipGuestCite(latestHostText);
  final pin = StringBuffer();
  if (user.isNotEmpty) {
    pin.write(
      ' Answer $userName\'s MOST RECENT line — not an earlier question',
    );
    if (host.isNotEmpty) {
      pin.write(', and not $hostName\'s reaction alone');
    }
    pin.write('. $userName just said: "$user".');
    if (host.isNotEmpty) {
      pin.write(' $hostName just said: "$host".');
    }
  }
  return '[SCENE GUEST TURN. You are now $guestName, who is '
      'present in this scene — you are NOT $hostName and NOT $userName. '
      'Everything written above was said and done by $hostName and '
      '$userName; $guestName is a separate person.$pin Reply ONLY '
      'as $guestName: their own dialogue, actions, and '
      'thoughts, reacting to what just happened. Do NOT write, speak, or '
      'narrate anything for $hostName or $userName.]\n';
}
