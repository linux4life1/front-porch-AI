// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Change graph asks ComfyUI for its three listings (Create templates, Edit
// templates, saved workflows) together, not one after another, against a real
// loopback server. A saved workflow that is not JSON has no nodes and does not
// throw.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/studio_graph_menu.dart';

void main() {
  setUp(() => HttpOverrides.global = null);

  test('the three listings are read together', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var inFlight = 0;
    var most = 0;
    server.listen((request) async {
      final path = request.uri.path;
      final listing = path == '/templates/index.json' || path == '/userdata';
      if (listing) most = ++inFlight > most ? inFlight : most;
      // Long enough that a request sent after the previous one has answered
      // would be seen not overlapping.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (listing) inFlight--;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<Object>[]));
      await request.response.close();
    });

    await loadDeskGraphMenus(
      comfy: ComfyUiService(baseUrl: 'http://127.0.0.1:${server.port}'),
    );

    expect(most, 3);
  });

  test('a saved workflow that is not JSON has no nodes', () {
    expect(workflowNodeCount('{ cut off'), 0);
    expect(workflowNodeCount('not json at all'), 0);
    expect(workflowNodeCount(''), 0);
    expect(workflowNodeCount('{"nodes": [{}, {}]}'), 2);
  });
}
