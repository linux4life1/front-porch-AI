// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Choose-files copies JSON recipe cards into library/tools/.
//
// Guard proven red: copying without the .json suffix check landed a .txt.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/user_tool_cards.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai_tools_copy_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('copyJsonFilesIntoTools copies json only', () async {
    final src = await Directory.systemTemp.createTemp('fpai_tools_src_');
    addTearDown(() async {
      if (await src.exists()) await src.delete(recursive: true);
    });
    final jsonFile = File('${src.path}/card.json');
    final txtFile = File('${src.path}/readme.txt');
    await jsonFile.writeAsString('{"name":"lookup"}');
    await txtFile.writeAsString('not a card');

    final tools = Directory('${root.path}/tools');
    final copied = copyJsonFilesIntoTools(tools, [jsonFile.path, txtFile.path]);
    expect(copied, 1);
    expect(File('${tools.path}/card.json').existsSync(), isTrue);
    expect(File('${tools.path}/readme.txt').existsSync(), isFalse);
  });
}
