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

// Navigate-first only works if isLoadingSession is true BEFORE the first
// await in setActiveCharacter / setActiveGroup. If the flag rises after
// cancel/settle/flush, ChatPage paints the previous transcript.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String methodHead(String path, String name) {
    final src = File(path).readAsStringSync();
    final start = src.indexOf('Future<void> $name');
    expect(start, greaterThanOrEqualTo(0), reason: 'could not find $name in $path');
    return src.substring(start, start + 900);
  }

  test('setActiveCharacter raises the overlay before the first await', () {
    final body = methodHead(
      'lib/services/chat/chat_service_chat_entry.dart',
      'setActiveCharacter',
    );
    final beginAt = body.indexOf('beginSessionLoad()');
    final firstAwait = body.indexOf('await ');
    expect(beginAt, greaterThanOrEqualTo(0));
    expect(firstAwait, greaterThan(beginAt));
  });

  test('setActiveGroup raises the overlay before the first await', () {
    final body = methodHead(
      'lib/services/chat/chat_service_group_entry.dart',
      'setActiveGroup',
    );
    final beginAt = body.indexOf('beginSessionLoad()');
    final firstAwait = body.indexOf('await ');
    expect(beginAt, greaterThanOrEqualTo(0));
    expect(firstAwait, greaterThan(beginAt));
  });
}
