// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// THE PHONE CREATOR'S REALISM STEP (#370), through the real relay.
//
// A character the creator saves records which first message its outfit was
// read from, on the card, and starts its Realism switch where Porch Life has
// the engine. The outfit hint asks once the first message changes, Keep
// settles it, and both survive a relay restart (the record is the card).
// Re-read runs the desktop's extraction; the scripted model's answer only
// feeds the save path under test (what is saved, what is left alone), never
// a claim about how a model reads a scene. Bad requests are refused, never
// run blank.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/web/facade/chargen/chargen_outfit.dart';

import 'dart:io';

import '../chargen/support/marker_chargen_llm.dart';
import 'support/chargen_relay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_outfit_').path;
        }
        return null;
      });

  /// A saved card whose outfit was read from [first].
  Future<String> savedCard(
    ChargenRelay relay, {
    String first = 'Hello.',
  }) async {
    final card = CharacterCard(
      name: 'Wren',
      firstMessage: first,
      frontPorchExtensions: FrontPorchExtensions(
        inventory: {
          'worn': [
            {'name': 'wool coat'},
          ],
          'carrying': const [],
        },
      ),
    );
    stampOutfitSource(card);
    final saved = await relay.characters.persistNewCard(card);
    return saved!['id'].toString();
  }

  Future<Map<String, dynamic>> realism(ChargenRelay relay, String id) async {
    final (_, d) = await relay.get('/api/characters/$id/detail');
    return Map<String, dynamic>.from(d['realism'] as Map);
  }

  List<String> worn(Map<String, dynamic> r) => [
    for (final i in ((r['inventory'] as Map?)?['worn'] as List? ?? const []))
      (i as Map)['name'].toString(),
  ];

  test(
    'the hint asks after a new first message; Keep settles it on the card',
    () async {
      final relay = await ChargenRelay.start(MarkerChargenLlm());
      final id = await savedCard(relay);

      var (code, body) = await relay.get('/api/chargen/outfit?characterId=$id');
      expect(code, 200);
      expect(body, {'changed': false, 'reading': false, 'error': null});

      await relay.post('/api/characters/$id', {'firstMessage': 'A new day.'});
      (code, body) = await relay.get('/api/chargen/outfit?characterId=$id');
      expect(body['changed'], isTrue);

      // A restarted relay reads the record from the card.
      final restarted = relay.restarted();
      (code, body) = await relay.get(
        '/api/chargen/outfit?characterId=$id',
        on: restarted,
      );
      expect(body['changed'], isTrue);

      (code, body) = await relay.post('/api/chargen/outfit/keep', {
        'characterId': id,
      });
      expect(code, 200, reason: '$body');
      expect(body['changed'], isFalse);
      (code, body) = await relay.get(
        '/api/chargen/outfit?characterId=$id',
        on: restarted,
      );
      expect(body['changed'], isFalse);
      // Keep left the outfit alone.
      expect(worn(await realism(relay, id)), ['wool coat']);
    },
  );

  test('a re-read saves the outfit read from the new first message', () async {
    final llm = MarkerChargenLlm(
      toolAnswers: {
        kPorchLifeToolName: {
          'worn': ['rain slicker'],
          'carrying': ['lantern'],
        },
      },
    );
    final relay = await ChargenRelay.start(llm);
    final id = await savedCard(relay);
    await relay.post('/api/characters/$id', {'firstMessage': 'Storm night.'});

    final done = relay.next('chargen_outfit_done');
    final (code, body) = await relay.post('/api/chargen/outfit/reread', {
      'characterId': id,
    });
    expect(code, 200, reason: '$body');
    expect((await done)['characterId'], id);
    // The extraction was asked about the first message as it reads now.
    expect(
      llm.promptWith('Seed Porch Life identity'),
      contains('Storm night.'),
    );
    final r = await realism(relay, id);
    expect(worn(r), ['rain slicker']);
    final (_, status) = await relay.get('/api/chargen/outfit?characterId=$id');
    expect(status['changed'], isFalse);
  });

  test('a re-read with no answer changes nothing and says so', () async {
    final llm = MarkerChargenLlm(
      textAnswers: {'Seed Porch Life identity': '{}'},
    );
    final relay = await ChargenRelay.start(llm);
    final id = await savedCard(relay);
    await relay.post('/api/characters/$id', {'firstMessage': 'Storm night.'});

    final failed = relay.next('chargen_outfit_error');
    final (code, _) = await relay.post('/api/chargen/outfit/reread', {
      'characterId': id,
    });
    expect(code, 200);
    expect((await failed)['error'], contains('Nothing was changed'));
    expect(worn(await realism(relay, id)), ['wool coat']);
    final (_, status) = await relay.get('/api/chargen/outfit?characterId=$id');
    expect(status['changed'], isTrue);
    expect(status['error'], contains('Nothing was changed'));
  });

  test('bad requests are refused', () async {
    final relay = await ChargenRelay.start(MarkerChargenLlm());
    expect((await relay.get('/api/chargen/outfit')).$1, 400);
    expect((await relay.get('/api/chargen/outfit?characterId=nope')).$1, 404);
    expect((await relay.post('/api/chargen/outfit/reread', {})).$1, 400);
    expect(
      (await relay.post('/api/chargen/outfit/reread', {'characterId': 'x'})).$1,
      404,
    );
    expect((await relay.post('/api/chargen/outfit/keep', {})).$1, 400);
    expect((await relay.postRaw('/api/chargen/outfit/keep', '{oops')).$1, 400);
    // A card the creator did not make never asks.
    final plain = await relay.characters.persistNewCard(
      CharacterCard(name: 'Plain', firstMessage: 'Hi.'),
    );
    final (_, status) = await relay.get(
      '/api/chargen/outfit?characterId=${plain!['id']}',
    );
    expect(status['changed'], isFalse);
  });

  test(
    'a created card records the first message its outfit was read from',
    () async {
      final relay = await ChargenRelay.start(MarkerChargenLlm());
      final done = relay.next('chargen_done', seconds: 60);
      final (code, body) = await relay.post('/api/chargen/create', {
        'name': 'Aria Vale',
        'mode': 'quick',
        'concept': 'A lighthouse keeper.',
      });
      expect(code, 200, reason: '$body');
      final id = (await done)['id'].toString();
      // The first message it was saved with is the outfit's source.
      var (_, status) = await relay.get('/api/chargen/outfit?characterId=$id');
      expect(status['changed'], isFalse);
      await relay.post('/api/characters/$id', {'firstMessage': 'Changed.'});
      (_, status) = await relay.get('/api/chargen/outfit?characterId=$id');
      expect(status['changed'], isTrue);
    },
  );
}
