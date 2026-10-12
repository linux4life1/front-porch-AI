// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Slow or failing work shows that it is happening, and says so when it
/// fails, instead of a dead tap.
class _HeldStore extends WaifuStore {
  _HeldStore() : super(Directory.systemTemp.path);

  final load = Completer<WaifuSession?>();
  var loads = 0;

  @override
  Future<WaifuSession?> loadSession(String folderRoot) {
    loads++;
    return load.future;
  }
}

/// Lets real file I/O in the manager finish, a frame at a time.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(done(), isTrue);
}

void main() {
  testWidgets('resume shows the card opening and reports a failed load', (
    tester,
  ) async {
    final store = _HeldStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaifuHomeView(
            store: store,
            projects: [
              WaifuProject(
                folderRoot: '/tmp/waifu-busy/toy',
                title: '',
                coworker: CharacterCard(name: 'Mira'),
                touchedMs: 2,
              ),
              WaifuProject(
                folderRoot: '/tmp/waifu-busy/other',
                title: '',
                coworker: CharacterCard(name: 'Iris'),
                touchedMs: 1,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waifu-resume')));
    await tester.pump();
    expect(find.byKey(const Key('waifu-opening')), findsOneWidget);

    await tester.tap(find.byKey(const Key('waifu-resume')));
    await tester.tap(find.byKey(const Key('waifu-project-other')));
    await tester.pump();
    expect(store.loads, 1, reason: 'other taps wait for the first open');

    store.load.completeError(const FileSystemException('unreadable'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('waifu-opening')), findsNothing);
    expect(find.textContaining('Could not open toy'), findsOneWidget);
  });

  testWidgets('a language download shows progress, then why it failed', (
    tester,
  ) async {
    final bytes = Completer<WaifuLangBytes>();
    final langs = WaifuLangRuntime(
      directory: Directory.systemTemp.path,
      catalog: const [
        WaifuLangDoor(
          id: 'toy',
          name: 'Toy',
          url: 'https://example.invalid/toy.bin',
          sha256: 'not-the-real-digest',
        ),
      ],
      fetch: (_) => bytes.future,
    );
    await tester.pumpWidget(MaterialApp(home: WaifuLanguageHelp(langs: langs)));
    await tester.tap(find.byKey(const Key('waifu-lang-toy')));
    await tester.pump();
    expect(find.byKey(const Key('waifu-lang-busy-toy')), findsOneWidget);
    expect(find.text('Setting up…'), findsOneWidget);

    bytes.complete(const WaifuLangBytes('https://example.invalid/toy.bin', []));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('waifu-lang-busy-toy')), findsNothing);
    expect(find.textContaining('checksum'), findsOneWidget);
    expect(langs.enabled, isEmpty);
  });

  testWidgets('the OpenCode download shows progress, then its failure', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('waifu_oc_busy_'),
    ))!;
    addTearDown(() => root.deleteSync(recursive: true));
    final download = Completer<List<int>>();
    final mgr = OpenCodeManager(
      rootPath: root.path,
      downloader: (url, {onProgress}) => download.future,
      unpack: (bytes, dest) async => fail('a failed download was unpacked'),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<OpenCodeManager>.value(
        value: mgr,
        child: const MaterialApp(home: Scaffold(body: WaifuOpenCodeStatus())),
      ),
    );
    await tester.runAsync(() async {
      await mgr.refreshInstalled();
    });
    await tester.pump();
    // Tapped on the real clock: the manager's file I/O cannot finish on
    // the test's fake one.
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('waifu-opencode-upgrade'))),
    );
    await _until(tester, () => mgr.isDownloading);
    expect(find.byKey(const Key('waifu-opencode-downloading')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    download.completeError(const SocketException('offline'));
    await _until(tester, () => !mgr.isDownloading);
    expect(find.byKey(const Key('waifu-opencode-downloading')), findsNothing);
    expect(find.byKey(const Key('waifu-opencode-error')), findsOneWidget);
    expect(find.textContaining('offline'), findsOneWidget);
  });
}
