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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:http/http.dart' as http;

void main() {
  test('webfetch refuses file:// and empty hosts', () async {
    final fetch = DeskWebFetch(
      sendRequest: (req) async => http.Response('LEAK', 200),
    );
    final file = await fetch.get('file:///etc/passwd');
    expect(file.ok, isFalse);
    expect(file.output, isNot(contains('LEAK')));

    final empty = await fetch.get('https://');
    expect(empty.ok, isFalse);
  });
}
