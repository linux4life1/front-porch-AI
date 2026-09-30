// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A ComfyUI graph sent from the phone is what Comfy runs on this computer, so
// storing one needs the web password, and the server checks the file itself:
// a real graph, within the size limit, for the mode it is meant for. Both
// ways in are covered: the file route and the config route.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/services/image/image.dart'
    show kComfyUploadedWorkflowId;
import 'package:front_porch_ai/services/web/facade/image_facade.dart'
    show kMaxDeskGraphBytes;

import 'image_desk_harness.dart';

const _createFile =
    'test/fixtures/comfy_templates/image_qwen_image_2_1_t2i.json';
const _editFile =
    'test/fixtures/comfy_templates/image_qwen_image_edit_2509_relight.json';

/// JSON as ComfyUI writes it into a PNG: ASCII only, other characters as
/// \\uXXXX escapes (a PNG text chunk is Latin-1).
String _asciiJson(String json) => json.replaceAllMapped(
  RegExp(r'[^\x00-\x7f]'),
  (m) => '\\u${m[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, "0")}',
);

/// A real PNG with a text chunk of [key] set to [text] before its end.
List<int> _png({String? key, String? text}) {
  final plain = img.encodePng(img.Image(width: 2, height: 2));
  if (key == null) return plain;
  final data = [...latin1.encode(key), 0, ...utf8.encode(text!)];
  final chunk = <int>[
    (data.length >> 24) & 255,
    (data.length >> 16) & 255,
    (data.length >> 8) & 255,
    data.length & 255,
    ...latin1.encode('tEXt'),
    ...data,
    0, 0, 0, 0, // The reader does not check the checksum.
  ];
  final end = plain.length - 12;
  return [...plain.sublist(0, end), ...chunk, ...plain.sublist(end)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DeskHarness h;
  late String createGraph;
  late String editGraph;

  setUp(() async {
    h = await DeskHarness.boot(comfy: await DeskComfy.start());
    createGraph = File(_createFile).readAsStringSync();
    editGraph = File(_editFile).readAsStringSync();
  });

  Future<(int, Map<String, dynamic>)> upload(
    List<int> bytes, {
    String name = 'my_graph.json',
    String mode = 'create',
    String? useFor,
    String? password = kDeskPassword,
  }) => h.call('POST', '/api/image/studio/graph', {
    'data': base64Encode(bytes),
    'name': name,
    'mode': mode,
    'useFor': ?useFor,
    'currentPassword': ?password,
  });

  group('a graph file', () {
    test('is stored for the mode it is for, with its name', () async {
      final (status, body) = await upload(utf8.encode(createGraph));

      expect(status, 200);
      expect(body['stored'], isTrue);
      expect(body['stance'], 'create');
      expect(body['nodes'], greaterThan(0));
      expect(h.settings.comfyCreateWorkflowId, kComfyUploadedWorkflowId);
      expect(h.settings.comfyCreateUploadedTitle, 'my_graph.json');
      expect(
        jsonDecode(h.settings.comfyCreateUploadedWorkflow),
        jsonDecode(createGraph),
      );
      expect(body['config']['comfyCreateUploadedWorkflow'], isTrue);
    });

    test('needs the web password', () async {
      final (none, body) = await upload(
        utf8.encode(createGraph),
        password: null,
      );
      final (wrong, _) = await upload(
        utf8.encode(createGraph),
        password: 'not-it',
      );

      expect(none, 401);
      expect(body['error'], 'Current password is incorrect');
      expect(wrong, 401);
      expect(h.settings.comfyCreateUploadedWorkflow, isEmpty);
      expect(h.settings.comfyCreateWorkflowId, isNot(kComfyUploadedWorkflowId));
    });

    test('for the other mode is not stored until the person says so', () async {
      final (status, body) = await upload(
        utf8.encode(editGraph),
        mode: 'create',
      );

      expect(status, 200);
      expect(body['stored'], isFalse);
      expect(body['stance'], 'edit');
      expect(h.settings.comfyCreateUploadedWorkflow, isEmpty);
      expect(h.settings.comfyEditUploadedWorkflow, isEmpty);

      final (again, stored) = await upload(
        utf8.encode(editGraph),
        mode: 'create',
        useFor: 'edit',
      );

      expect(again, 200);
      expect(stored['stored'], isTrue);
      expect(stored['mode'], 'edit');
      expect(h.settings.comfyEditWorkflowId, kComfyUploadedWorkflowId);
      expect(h.settings.comfyCreateUploadedWorkflow, isEmpty);
    });

    test('that names neither mode asks which, then obeys', () async {
      // A graph with nodes but no picture-making mark.
      final neither = jsonEncode({
        '1': {'class_type': 'Note', 'inputs': <String, dynamic>{}},
      });

      final (_, ask) = await upload(utf8.encode(neither));
      expect(ask['stored'], isFalse);
      expect(ask['stance'], 'unstated');

      final (_, done) = await upload(utf8.encode(neither), useFor: 'create');
      expect(done['stored'], isTrue);
      expect(h.settings.comfyCreateWorkflowId, kComfyUploadedWorkflowId);
    });

    test('use it for something that is not a mode is refused', () async {
      final (status, body) = await upload(
        utf8.encode(createGraph),
        useFor: 'delete',
      );

      expect(status, 400);
      expect(body['code'], 'bad_request');
      expect(h.settings.comfyCreateUploadedWorkflow, isEmpty);
    });

    test('that is not a graph is refused and nothing is stored', () async {
      for (final text in ['just words', '[1,2,3]', '{}', '{"a": 1}']) {
        final (status, body) = await upload(utf8.encode(text));
        expect(status, 400, reason: text);
        expect(body['code'], 'not_graph', reason: text);
      }
      expect(h.settings.comfyCreateUploadedWorkflow, isEmpty);
    });

    test('too large is refused', () async {
      final big = utf8.encode(
        '{"1": {"class_type": "KSampler"}, "pad": "'
        '${'x' * (kMaxDeskGraphBytes + 1)}"}',
      );

      final (status, body) = await upload(big);

      expect(status, 413);
      expect(body['code'], 'too_large');
      expect(h.settings.comfyCreateUploadedWorkflow, isEmpty);
    });

    test('in a PNG Comfy saved is found and stored', () async {
      final (status, body) = await upload(
        _png(key: 'prompt', text: _asciiJson(createGraph)),
        name: 'made.png',
      );

      expect(status, 200);
      expect(body['stored'], isTrue);
      expect(h.settings.comfyCreateUploadedTitle, 'made.png');
      expect(
        jsonDecode(h.settings.comfyCreateUploadedWorkflow),
        jsonDecode(createGraph),
      );
    });

    test('a PNG with no graph inside says so', () async {
      final (status, body) = await upload(_png(), name: 'plain.png');

      expect(status, 400);
      expect(body['code'], 'no_graph_in_image');
      expect(body['error'], contains('no ComfyUI workflow'));
    });
  });

  group('a graph sent through the config', () {
    test('needs the web password', () async {
      final (status, _) = await h.call('POST', '/api/image/config', {
        'comfyCreateUploadedWorkflow': createGraph,
      });

      expect(status, 401);
      expect(h.settings.comfyCreateUploadedWorkflow, isEmpty);
    });

    test('is checked, and a refused one leaves the rest as it was', () async {
      final before = h.settings.imageGenSteps;

      final (status, body) = await h.call('POST', '/api/image/config', {
        'steps': before + 7,
        'comfyCreateUploadedWorkflow': 'not a graph',
        'currentPassword': kDeskPassword,
      });

      expect(status, 400);
      expect(body['code'], 'not_graph');
      expect(h.settings.imageGenSteps, before);
      expect(h.settings.comfyCreateUploadedWorkflow, isEmpty);
    });

    test('JSON with no nodes in it is not a graph either', () async {
      for (final text in ['{}', '{"a": 1}', '[]', '"x"']) {
        final (status, body) = await h.call('POST', '/api/image/config', {
          'comfyEditUploadedWorkflow': text,
          'currentPassword': kDeskPassword,
        });
        expect(status, 400, reason: text);
        expect(body['code'], 'not_graph', reason: text);
      }
      expect(h.settings.comfyEditUploadedWorkflow, isEmpty);
    });

    test('a real one is stored with its title', () async {
      final (status, _) = await h.call('POST', '/api/image/config', {
        'comfyEditUploadedWorkflow': editGraph,
        'comfyEditUploadedTitle': 'relight.json',
        'currentPassword': kDeskPassword,
      });

      expect(status, 200);
      expect(h.settings.comfyEditUploadedTitle, 'relight.json');
      expect(jsonDecode(h.settings.comfyEditUploadedWorkflow), isA<Map>());
    });

    test('clearing one needs no password', () async {
      await h.settings.setComfyCreateUploadedWorkflow(
        createGraph,
        title: 'old.json',
      );

      final (status, _) = await h.call('POST', '/api/image/config', {
        'comfyCreateUploadedWorkflow': '',
      });

      expect(status, 200);
      expect(h.settings.comfyCreateUploadedWorkflow, isEmpty);
    });

    test('ordinary settings still need no password', () async {
      final (status, _) = await h.call('POST', '/api/image/config', {
        'steps': 30,
      });

      expect(status, 200);
      expect(h.settings.imageGenSteps, 30);
    });
  });
}
