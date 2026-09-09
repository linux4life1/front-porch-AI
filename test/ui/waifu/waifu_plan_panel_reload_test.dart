// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: mutate session.activePlanPath on the same object, parent
// setState, panel still said "No plan file yet" because didUpdateWidget
// compared oldWidget.session to widget.session (identical instance).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('in-place session pin is invisible unless pin is copied at build', () {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
      mode: WaifuMode.plan,
    );
    final previousPin = session.activePlanPath;
    final previousWrite = session.lastWrite?.relativePath;
    session.activePlanPath = '.waifu/plans/swift-epub-reader.md';
    session.lastWrite = const WaifuWriteRecord(
      relativePath: '.waifu/plans/swift-epub-reader.md',
      before: '',
      after: 'x',
    );
    expect(
      session.activePlanPath == session.activePlanPath,
      isTrue,
      reason: 'same object: oldWidget.session.pin already equals new pin',
    );
    expect(
      waifuPlanPanelShouldReload(
        previousPin: previousPin,
        nextPin: session.activePlanPath,
        previousWrite: previousWrite,
        nextWrite: session.lastWrite?.relativePath,
        previousMode: session.mode,
        nextMode: session.mode,
      ),
      isTrue,
    );
  });

  test(
    'plan panel copies pin/lastWrite at build, not off the live session',
    () {
      final src = File('lib/ui/waifu/waifu_plan_panel.dart').readAsStringSync();
      expect(src, contains('pinnedPath = session.activePlanPath'));
      expect(src, contains('lastWritePath = session.lastWrite?.relativePath'));
      expect(src, contains('waifuPlanPanelShouldReload'));
      expect(
        src,
        isNot(
          contains(
            'oldWidget.session.activePlanPath != widget.session.activePlanPath',
          ),
        ),
      );
    },
  );
}
