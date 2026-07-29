// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Sandbox + pump helpers for the E2E suite. See app_smoke_test.dart for the
// isolation contract these enforce.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// CI runners (2-core VMs) are several times slower than a dev machine, and
/// every timeout in this suite was tuned locally. All wait helpers multiply
/// their timeouts by this factor; GitHub Actions always sets CI=true.
final int kCiTimeoutScale =
    Platform.environment['CI'] == 'true' ? 4 : 1;

/// Redirects every path_provider lookup into [root] so the app cannot touch
/// the real installation. Extends (not implements) PathProviderPlatform so
/// the platform-interface token check accepts it.
class SandboxPathProvider extends PathProviderPlatform {
  SandboxPathProvider(this.root);

  final String root;

  String _dir(String name) =>
      (Directory(p.join(root, name))..createSync(recursive: true)).path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('Documents');

  @override
  Future<String?> getApplicationSupportPath() async =>
      _dir('ApplicationSupport');

  @override
  Future<String?> getLibraryPath() async => _dir('Library');

  @override
  Future<String?> getApplicationCachePath() async => _dir('Caches');

  @override
  Future<String?> getTemporaryPath() async => _dir('tmp');

  @override
  Future<String?> getDownloadsPath() async => _dir('Downloads');
}

/// Real-async equivalent of pumpAndSettle for a live app: boot and post-gen
/// eval chains complete on real async gaps, and the app keeps periodic
/// animations running, so pumpAndSettle would never settle. Pump until
/// [finder] matches or fail.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  timeout *= kCiTimeoutScale;
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      // Post-mortem hint: distinguishes "runApp never happened" (tree empty —
      // main() died before runApp) from "app stuck before home" (tree has
      // widgets but never mounted the target).
      fail(
        'Timed out after $timeout waiting for $finder. '
        'Widget tree currently holds ${tester.allWidgets.length} widgets.',
      );
    }
    await _pumpGuarded(tester);
  }
}

/// One 250ms pump that CANNOT hang: if the binding stops producing frames
/// (the classic cause: a real mouse hover over the live test window wedges
/// the gesture binding's hit-test bookkeeping), fail with the explanation
/// instead of awaiting a frame that never comes.
Future<void> _pumpGuarded(WidgetTester tester) async {
  try {
    await tester
        .pump(const Duration(milliseconds: 250))
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    fail(
      'The binding stopped producing frames (pump hung for 10s). This '
      'usually means the physical mouse interacted with the live test '
      'window — keep hands off the machine while the E2E suite runs.',
    );
  }
}

/// Pump until [condition] is true or fail with [describe]. For state that
/// isn't a widget (service fields, fake-server counters).
Future<void> pumpUntilTrue(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 60),
  // Lazy so the failure message can include live state (service fields,
  // fake-server counters) as of the moment the timeout fired.
  required String Function() describe,
}) async {
  timeout *= kCiTimeoutScale;
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout waiting for: ${describe()}');
    }
    await _pumpGuarded(tester);
  }
}
