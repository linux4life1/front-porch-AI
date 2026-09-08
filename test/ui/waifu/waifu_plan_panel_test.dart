// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_plan_panel.dart';

void main() {
  test('sidebar hosts a real Plan panel, not a mode chip', () {
    final sidebar = File('lib/ui/waifu/waifu_sidebar.dart').readAsStringSync();
    final panel = File('lib/ui/waifu/waifu_plan_panel.dart').readAsStringSync();
    final page = File('lib/ui/waifu/waifu_page.dart').readAsStringSync();
    expect(sidebar, contains('WaifuPlanPanel'));
    expect(sidebar, contains("id: 'waifu_plan'"));
    expect(panel, contains("Key('waifu-plan-accept')"));
    expect(panel, contains("Key('waifu-plan-revise')"));
    expect(panel, contains("Key('waifu-plan-discard')"));
    expect(panel, contains("Key('waifu-plan-body')"));
    expect(panel, contains('Accept → Build'));
    expect(page, contains('harness: harness'));
    expect(
      WaifuPlanPanel(
        session: WaifuSession(
          folderRoot: '/tmp',
          coworker: CharacterCard(name: 'Mira'),
          mode: WaifuMode.plan,
        ),
      ),
      isA<Widget>(),
    );
  });
}
