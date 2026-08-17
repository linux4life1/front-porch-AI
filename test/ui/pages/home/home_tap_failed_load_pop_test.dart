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

// A failed home-grid load used to debugPrint and still await the ChatPage
// route, so the user sat on a half-hydrated transcript. The catch must
// pop the page we just pushed and snack the failure.
//
// Same source-read seam as home_tap_navigate_first_test: the helper is a
// private part-file method behind Provider + a route. No HomePage pump.

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

  test('_pushChatWhile catch pops ChatPage and snacks the failure', () {
    final body = handler('_pushChatWhile');
    final catchAt = body.indexOf('catch (');
    expect(
      catchAt,
      greaterThanOrEqualTo(0),
      reason:
          'a failed load must be caught — swallowing it is the ghost transcript',
    );
    final catchBody = body.substring(catchAt);
    expect(
      catchBody,
      contains('nav.pop()'),
      reason: 'ChatPage is already pushed; catch must pop it',
    );
    expect(catchBody, contains('Could not open chat'));
  });
}
