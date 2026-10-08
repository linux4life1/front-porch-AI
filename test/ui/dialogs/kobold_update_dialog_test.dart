// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The start-up box about the managed KoboldCpp. The red box (below the
// floor) has no way out but the update or removing the engine; the amber
// box (a newer release) can be put off for three days. The update is a real
// download, from a server on loopback, through the same manager the
// Settings page uses; what it writes is checked on disk.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/dialogs/kobold_update_dialog.dart';
import 'package:path/path.dart' as p;

import '../../services/kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

/// The engine download from [url]; the GitHub lookup is seeded instead.
class _Manager extends BackendManager {
  _Manager(super.storage, this.url)
    : super(onMac: Platform.isMacOS, readArch: () async => 'arm64');
  final String url;
  @override
  String get engineDownloadUrl => url;
  @override
  Future<void> checkForUpdates() async {}
}

/// A loopback server answering every request with [body], or a 500.
Future<HttpServer> _serve(List<int> body, {bool fail = false}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((r) async {
    if (fail) {
      r.response.statusCode = HttpStatus.internalServerError;
    } else {
      r.response
        ..contentLength = body.length
        ..add(body);
    }
    await r.response.close();
  });
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();
  late StorageService storage;
  late Directory bin;
  late String engine;
  final body = List.filled(2 * 1024 * 1024, 7);

  setUp(() async {
    HttpOverrides.global = null;
    storage = await createStorageService();
    bin = storage.binDir;
    await bin.create(recursive: true);
    // An engine file the manager finds on this machine, 2 KB of nothing.
    engine = p.join(bin.path, _executableName());
    File(engine).writeAsBytesSync(List.filled(2048, 1));
  });
  tearDown(() {
    if (bin.existsSync()) bin.deleteSync(recursive: true);
  });

  Future<_Manager> open(
    WidgetTester tester, {
    required String url,
    required String recordVersion,
    String? remote,
  }) async {
    // Under runAsync: the record is written to disk, and the manager's
    // first look for the engine runs real processes (chmod, xattr); the
    // test's fake clock would hold both.
    final manager = (await tester.runAsync(() async {
      await KoboldBinaryVersion.write(
        bin.path,
        version: recordVersion,
        size: 2048,
      );
      final m = _Manager(storage, url);
      await m.engineChecked;
      return m;
    }))!;
    addTearDown(manager.dispose);
    if (remote != null) {
      manager.seedRemoteVersion(remote, assetSize: body.length);
    }
    final gate = await tester.runAsync(
      () => manager.updateGate(autoCheck: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => KoboldUpdateDialog.show(context, manager, gate!),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return manager;
  }

  /// Real time for the download, and the fake clock moved with it (the
  /// manager pauses half a second after a download), until [done].
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
    await tester.pumpAndSettle();
    expect(done(), isTrue);
  }

  testWidgets('below the floor: the red box cannot be dismissed, and Update '
      'now installs the new engine and its record', (tester) async {
    final server = (await tester.runAsync(() => _serve(body)))!;
    addTearDown(() => server.close(force: true));
    final manager = await open(
      tester,
      url: 'http://127.0.0.1:${server.port}/koboldcpp',
      recordVersion: '1.100',
      remote: '1.130',
    );
    expect(find.text('KoboldCpp is too old to run'), findsOneWidget);
    expect(find.textContaining('KoboldCpp 1.100'), findsOneWidget);
    expect(find.text('Not now'), findsNothing);
    // Esc and the back gesture go through maybePop; the box stays.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('KoboldCpp is too old to run'), findsOneWidget);

    await tester.tap(find.text('Update now'));
    await settle(tester, () => find.text('Done').evaluate().isNotEmpty);
    expect(
      find.text('KoboldCpp 1.130 is installed and ready.'),
      findsOneWidget,
    );
    final installed = manager.backendPath!;
    expect(File(installed).lengthSync(), body.length, reason: 'the new engine');
    expect(
      await tester.runAsync(() => KoboldBinaryVersion.versionFor(installed)),
      '1.130',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(KoboldUpdateDialog), findsNothing);
    expect(
      await tester.runAsync(() => manager.updateGate(autoCheck: true)),
      KoboldUpdateGate.nothing,
      reason: 'the next start shows nothing',
    );
  });

  testWidgets('below the floor: Remove it deletes the engine and its record, '
      'and the app counts KoboldCpp as not installed', (tester) async {
    final manager = await open(
      tester,
      url: 'http://127.0.0.1:1/none',
      recordVersion: '1.100',
    );
    await tester.tap(find.text('Remove it, I use something else'));
    await settle(
      tester,
      () => find.byType(KoboldUpdateDialog).evaluate().isEmpty,
    );
    expect(File(engine).existsSync(), isFalse);
    expect(
      File(p.join(bin.path, KoboldBinaryVersion.fileName)).existsSync(),
      isFalse,
    );
    expect(manager.backendPath, isNull);
    expect(
      await tester.runAsync(() => manager.updateGate(autoCheck: true)),
      KoboldUpdateGate.nothing,
    );
  });

  testWidgets('a newer release: Not now holds it three days for that release', (
    tester,
  ) async {
    final manager = await open(
      tester,
      url: 'http://127.0.0.1:1/none',
      recordVersion: '1.120',
      remote: '1.130',
    );
    expect(find.text('KoboldCpp has an update'), findsOneWidget);
    expect(find.textContaining('KoboldCpp 1.130 is out'), findsOneWidget);
    expect(find.text('Remove it, I use something else'), findsNothing);
    final before = DateTime.now();
    await tester.tap(find.text('Not now'));
    await settle(
      tester,
      () => find.byType(KoboldUpdateDialog).evaluate().isEmpty,
    );
    final snooze = await tester.runAsync(() => manager.readUpdateSnooze());
    expect(snooze!.version, '1.130');
    expect(
      snooze.until!.difference(before).inMinutes,
      closeTo(kKoboldUpdateSnooze.inMinutes, 1),
    );
    expect(
      await tester.runAsync(() => manager.updateGate(autoCheck: true)),
      KoboldUpdateGate.nothing,
    );
    expect(
      await tester.runAsync(
        () => manager.updateGate(
          autoCheck: true,
          now: DateTime.now().add(const Duration(days: 4)),
        ),
      ),
      KoboldUpdateGate.newer,
      reason: 'the hold runs out',
    );
    manager.seedRemoteVersion('1.131', assetSize: body.length);
    expect(
      await tester.runAsync(() => manager.updateGate(autoCheck: true)),
      KoboldUpdateGate.newer,
      reason: 'a release after the snoozed one asks at once',
    );
  });

  testWidgets('a failed download says so and offers Try again, with Remove '
      'it still there below the floor', (tester) async {
    final server = (await tester.runAsync(() => _serve(body, fail: true)))!;
    addTearDown(() => server.close(force: true));
    await open(
      tester,
      url: 'http://127.0.0.1:${server.port}/koboldcpp',
      recordVersion: '1.100',
      remote: '1.130',
    );
    await tester.tap(find.text('Update now'));
    await settle(tester, () => find.text('Try again').evaluate().isNotEmpty);
    expect(find.textContaining('The download did not finish'), findsOneWidget);
    expect(find.text('Remove it, I use something else'), findsOneWidget);
    expect(File(engine).lengthSync(), 2048, reason: 'the old engine stays');
  });
}

String _executableName() {
  if (Platform.isWindows) return 'koboldcpp.exe';
  if (Platform.isMacOS) return 'koboldcpp-mac-arm64';
  return 'koboldcpp-linux-x64-nocuda';
}
