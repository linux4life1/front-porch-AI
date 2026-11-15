// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// THE PHONE CREATOR'S REALISM STEP, through the real relay: a character the
// AI creator saves starts its Realism switch where Porch Life has the engine
// (`realismDefault`), as the desktop creator's Realism step does (ruling
// 2026-10-14), so the web step opens on that value. The step itself saves
// through the editor's update route, which changes only the keys it is sent:
// a Realism save leaves the greetings and profile as they were.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chargen/support/marker_chargen_llm.dart';
import 'support/chargen_relay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_creator_rl_').path;
        }
        return null;
      });

  Future<String> create(ChargenRelay relay) async {
    final done = relay.next('chargen_done', seconds: 60);
    final (code, body) = await relay.post('/api/chargen/create', {
      'name': 'Aria Vale',
      'mode': 'quick',
      'concept': 'A lighthouse keeper.',
    });
    expect(code, 200, reason: '$body');
    return (await done)['id'].toString();
  }

  Future<Map<String, dynamic>> detail(ChargenRelay relay, String id) async {
    final (_, d) = await relay.get('/api/characters/$id/detail');
    return d;
  }

  test('a created card starts Realism where Porch Life has it', () async {
    final relay = await ChargenRelay.start(MarkerChargenLlm());
    await relay.storage.realismSettings.setRealismDefault(true);
    final on = await create(relay);
    expect((await detail(relay, on))['realism']['realismEnabled'], isTrue);

    await relay.storage.realismSettings.setRealismDefault(false);
    final off = await create(relay);
    expect((await detail(relay, off))['realism']['realismEnabled'], isFalse);
  });

  test('a Realism-only save keeps the greetings and profile', () async {
    final relay = await ChargenRelay.start(MarkerChargenLlm());
    final id = await create(relay);
    await relay.post('/api/characters/$id', {
      'firstMessage': 'Edited by hand.',
      'description': 'Kept.',
    });
    final (code, _) = await relay.post('/api/characters/$id', {
      'realismEnabled': false,
      'occupation': 'ferry pilot',
    });
    expect(code, 200);
    final d = await detail(relay, id);
    expect(d['firstMessage'], 'Edited by hand.');
    expect(d['description'], 'Kept.');
    expect(d['realism']['occupation'], 'ferry pilot');
    expect(d['realism']['realismEnabled'], isFalse);
  });
}
