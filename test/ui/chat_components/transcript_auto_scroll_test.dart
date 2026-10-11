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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('send and ChatPage no longer pin the transcript', () {
    final input = File('lib/ui/pages/chat_page.input.dart').readAsStringSync();
    expect(input.contains('_scrollToBottom'), isFalse);
    final page = File('lib/ui/pages/chat_page.dart').readAsStringSync();
    expect(page.contains('void _scrollToBottom'), isFalse);
    expect(page.contains('bool _autoScroll'), isFalse);
  });
}
