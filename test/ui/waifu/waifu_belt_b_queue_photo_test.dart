// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_composer.dart';

Uint8List _png() => Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/'
    'ESuzjQAAAABJRU5ErkJggg==',
  ),
);

void main() {
  testWidgets('B1: attach stays live while busy; queued photo is visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    )..running = true;
    session.queued.add(
      WaifuQueuedFollowUp(
        text: 'what is this',
        imagePng: _png(),
        imagePath: 'shot.png',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaifuComposer(
            controller: TextEditingController(),
            session: session,
            onSend: () {},
            onPickSlash: (_) {},
            onStop: () {},
            onUndo: () {},
            onRedo: () {},
            onAttach: () {},
            onDropImage: (_) async {},
          ),
        ),
      ),
    );
    final attach = tester.widget<IconButton>(
      find.byKey(const Key('waifu-attach-photo')),
    );
    expect(attach.onPressed, isNotNull);
    expect(find.byKey(const Key('waifu-queued-0')), findsOneWidget);
    expect(find.byKey(const Key('waifu-queued-0-photo')), findsOneWidget);
    expect(find.text('what is this'), findsWidgets);
  });
}
