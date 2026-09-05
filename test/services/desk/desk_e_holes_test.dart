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
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_e_holes_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('@.env does not attach secrets', () async {
    await File(p.join(root.path, '.env')).writeAsString('SECRET=do-not-leak');
    final attached = await deskExpandMentions('read @.env', root.path);
    expect(attached, isNot(contains('SECRET')));
  });

  test('huge @file is clipped', () async {
    final huge = 'x' * (kDeskReadClipChars + 5000);
    await File(p.join(root.path, 'big.txt')).writeAsString(huge);
    final attached = await deskExpandMentions('see @big.txt', root.path);
    expect(attached.length, lessThan(kDeskReadClipChars + 200));
    expect(attached, contains('clipped'));
  });

  test('skill name with .. does not escape the jail', () async {
    final leaked = await deskLoadSkill(root.path, '../../etc/passwd');
    expect(leaked.toLowerCase(), contains('not found'));
    expect(leaked, isNot(contains('root:')));
  });
}
