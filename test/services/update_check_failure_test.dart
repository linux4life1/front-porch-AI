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

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/update_service.dart';

// Regression coverage for the in-app updater claiming "You are up to date"
// during a GitHub outage. A failed check used to return false exactly like a
// successful "nothing newer" check, so the UI could not tell them apart. The
// KoboldCpp and OpenCode updaters already say "check failed" here; this one
// must expose the failure through [UpdateService.checkError].
//
// Every case talks real HTTP to a real listening server the test controls.
void main() {
  late HttpServer server;
  late int status;
  late String body;

  setUp(() async {
    // flutter_test answers every request with a canned 400; this suite needs
    // the real HTTP stack against the real server below.
    HttpOverrides.global = null;
    status = 200;
    body = '[]';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..statusCode = status
        ..write(body)
        ..close();
    });
    UpdateService.debugIsSupportedOverride = true;
    UpdateService.debugApiBaseOverride =
        'http://${server.address.host}:${server.port}';
  });

  tearDown(() async {
    UpdateService.debugIsSupportedOverride = null;
    UpdateService.debugApiBaseOverride = null;
    await server.close(force: true);
  });

  test('a GitHub 5xx is reported as a failed check, not up to date', () async {
    status = 503;
    body = 'unicorn';
    final service = UpdateService();

    expect(await service.checkForUpdate(), isFalse);
    expect(service.checkError, contains('503'));
    expect(service.checking, isFalse);
  });

  test('an unreachable host is reported as a failed check', () async {
    await server.close(force: true);
    final service = UpdateService();

    expect(await service.checkForUpdate(), isFalse);
    expect(service.checkError, isNotNull);
  });

  test('an error object instead of a release list is a failed check', () async {
    body = jsonEncode({'message': 'Server Error'});
    final service = UpdateService();

    expect(await service.checkForUpdate(), isFalse);
    expect(service.checkError, isNotNull);
  });

  test('a good reply with nothing newer clears a previous failure', () async {
    status = 502;
    final service = UpdateService();
    await service.checkForUpdate();
    expect(service.checkError, isNotNull);

    status = 200;
    body = '[]';
    expect(await service.checkForUpdate(), isFalse);
    expect(service.checkError, isNull);
  });
}
