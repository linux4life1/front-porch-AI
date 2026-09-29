// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Change graph reads a real loopback ComfyUI: the three listings at once,
// every saved workflow at once and only once, and an Edit graph wrapped in a
// subgraph (the official layout) listed under Edit, not Create.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/studio_graph_menu.dart';

const _fixtures = 'test/fixtures/comfy_templates';

class _Comfy {
  _Comfy(this.server);

  final HttpServer server;
  final hits = <String, int>{};
  var inFlight = 0;
  var mostInFlight = 0;

  String get url => 'http://127.0.0.1:${server.port}';
}

/// Serves [saved] as Desktop workflows. Every workflow read waits a moment so
/// that reads which overlap are seen overlapping.
Future<_Comfy> _serve(Map<String, String> saved) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final comfy = _Comfy(server);
  server.listen((request) async {
    final path = Uri.decodeComponent(request.uri.path);
    comfy.hits[path] = (comfy.hits[path] ?? 0) + 1;
    request.response.headers.contentType = ContentType.json;
    if (path == '/userdata' && request.uri.query == 'dir=workflows') {
      request.response.write(jsonEncode(saved.keys.toList()));
    } else if (path.startsWith('/userdata/workflows/')) {
      comfy.mostInFlight = ++comfy.inFlight > comfy.mostInFlight
          ? comfy.inFlight
          : comfy.mostInFlight;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      comfy.inFlight--;
      final body = saved[path.substring('/userdata/workflows/'.length)];
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.write(body);
      }
    } else if (path == '/templates/index.json') {
      request.response.write('[]');
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  addTearDown(() => server.close(force: true));
  return comfy;
}

String _fixture(String name) => File('$_fixtures/$name').readAsStringSync();

void main() {
  setUp(() => HttpOverrides.global = null);

  final saved = {
    'relight.json': _fixture('image_qwen_image_edit_2509_relight.json'),
    'klein.json': _fixture('image_flux2_klein_text_to_image.json'),
    'qwen21.json': _fixture('image_qwen_image_2_1_t2i.json'),
    'layered.json': _fixture('image_qwen_image_layered_control.json'),
  };

  test('an Edit graph inside a subgraph is an Edit graph', () {
    final relight = jsonDecode(saved['relight.json']!) as Map<String, dynamic>;
    // The only edit node is inside the subgraph, not at the top level.
    final top = {
      for (final node in relight['nodes'] as List)
        (node as Map)['type'].toString(),
    };
    expect(top.any((t) => t.contains('ImageEdit')), isFalse);
    expect(savedGraphIsEdit(relight), isTrue);
    expect(
      savedGraphIsEdit(
        jsonDecode(saved['klein.json']!) as Map<String, dynamic>,
      ),
      isFalse,
    );
  });

  test('both lists come from one read of each saved workflow', () async {
    final comfy = await _serve(saved);
    final menus = await loadDeskGraphMenus(
      comfy: ComfyUiService(baseUrl: comfy.url),
    );
    List<String> savedIds(List<DeskGraphChoice> rows) => [
      for (final row in rows)
        if (row.group == 'Saved on this Comfy') row.id,
    ];
    expect(savedIds(menus.edit), contains('comfy:userdata:relight'));
    expect(
      savedIds(menus.create),
      containsAll(['comfy:userdata:klein', 'comfy:userdata:qwen21']),
    );
    expect(savedIds(menus.create), isNot(contains('comfy:userdata:relight')));
    // Every saved file is in exactly one list.
    for (final name in saved.keys) {
      final id = 'comfy:userdata:${name.replaceAll('.json', '')}';
      expect(
        [
          savedIds(menus.create),
          savedIds(menus.edit),
        ].where((ids) => ids.contains(id)),
        hasLength(1),
        reason: name,
      );
    }
    for (final name in saved.keys) {
      expect(comfy.hits['/userdata/workflows/$name'], 1, reason: name);
    }
  });

  test('saved workflows are read together, not one after another', () async {
    final comfy = await _serve(saved);
    await loadDeskGraphMenus(comfy: ComfyUiService(baseUrl: comfy.url));
    expect(comfy.mostInFlight, saved.length);
  });
}
