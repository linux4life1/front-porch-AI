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

// Home used to await setActiveCharacter (cancel + flush + 17–85 messages +
// realism + RAG) BEFORE pushing ChatPage, so a tap froze the grid. ChatPage
// already has an isLoadingSession overlay — the route must leave first.
//
// Same source-read seam as home_tap_session_identity_test: the handler is a
// private part-file method behind Provider + a route.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/ui/pages/home/home_page_chrome.dart').readAsStringSync();
  });

  String handler(String name) {
    final start = src.indexOf('Future<void> $name');
    expect(
      start,
      greaterThanOrEqualTo(0),
      reason: 'could not read $name — move this guard with the method',
    );
    return src.substring(start, start + 1800);
  }

  test('character tap pushes ChatPage without awaiting the hydrate', () {
    final body = handler('_handleTapCharacter');
    expect(body, contains('_pushChatWhile'));
    final pushAt = body.indexOf('_pushChatWhile');
    final awaitAt = body.indexOf('await chatService.setActiveCharacter');
    expect(
      awaitAt == -1 || awaitAt > pushAt,
      isTrue,
      reason: 'awaiting setActiveCharacter before _pushChatWhile is the grid freeze',
    );
    expect(body, contains('_getCharacterIdFromCard(character)'));
  });

  test('group tap pushes ChatPage without awaiting the hydrate', () {
    final body = handler('_handleTapGroup');
    expect(body, contains('_pushChatWhile'));
    final pushAt = body.indexOf('_pushChatWhile');
    final awaitAt = body.indexOf('await chatService.setActiveGroup');
    expect(
      awaitAt == -1 || awaitAt > pushAt,
      isTrue,
      reason: 'group tap must leave the grid the same way 1:1 does',
    );
  });

  test('Start New Chat pushes ChatPage without awaiting startFreshChatWith', () {
    final body = handler('_startNewChatWith');
    expect(body, contains('_pushChatWhile'));
    expect(body.contains('await chatService.startFreshChatWith'), isFalse);
  });
}
