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

void main() {
  test('cd \$HOME, pushd /, and CD / are denied before spawn', () {
    expect(deskBashBlocked('cd \$HOME && pwd'), isNotNull);
    expect(deskBashBlocked('cd \${HOME} && pwd'), isNotNull);
    expect(deskBashBlocked('pushd / && pwd'), isNotNull);
    expect(deskBashBlocked('CD / && pwd'), isNotNull);
    expect(deskBashBlocked('builtin cd /'), isNotNull);
    expect(deskBashBlocked('cd src && ls'), isNull);
    expect(deskBashBlocked('pwd'), isNull);
  });
}
