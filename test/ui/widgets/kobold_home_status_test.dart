// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The home screen's line about the local engine. Why KoboldCpp stopped on
// its own sits on its status line until the next Start or Stop, and the home
// screen showed that line whatever chat ran on: a user who had moved chat to
// a remote service kept reading why a KoboldCpp they no longer use stopped.
// The phone shows it only while chat runs on KoboldCpp (its Models page
// shows the local cards only then). Now the desktop does the same; what a
// load is doing is still said either way, since a helper model may run on
// the engine while chat is remote.
//
// The real wrapper the home page puts under its content, with the engine
// and the chat backend as the home page reads them.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';

/// Stopped, or starting (the phase follows from these, as on the real one).
class _Kobold extends FakeKoboldService {
  _Kobold(this._status, {required this.starting});
  final String _status;
  final bool starting;

  @override
  String get modelLoadingStatus => _status;

  @override
  bool get isStarting => starting;
}

void main() {
  const why =
      'KoboldCpp ran out of graphics memory while loading the model. Try a '
      'smaller context size or a stronger cache compression.';

  Future<void> show(
    WidgetTester tester, {
    required String status,
    required KoboldPhase phase,
    required BackendType chat,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KoboldService>.value(
            value: _Kobold(status, starting: phase == KoboldPhase.starting),
          ),
          ChangeNotifierProvider<LLMProvider>.value(
            value: FakeLLMProvider(activeBackend: chat),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: KoboldHomeStatus(child: Text('the library'))),
        ),
      ),
    );
  }

  testWidgets('chat on KoboldCpp: why it stopped is said', (tester) async {
    await show(
      tester,
      status: why,
      phase: KoboldPhase.stopped,
      chat: BackendType.kobold,
    );

    expect(find.text(why), findsOneWidget);
    expect(find.text('the library'), findsOneWidget);
  });

  testWidgets('chat on a remote service: a stopped KoboldCpp is not news', (
    tester,
  ) async {
    await show(
      tester,
      status: why,
      phase: KoboldPhase.stopped,
      chat: BackendType.openRouter,
    );

    expect(find.text(why), findsNothing);
    expect(find.byType(KoboldStatusBar), findsNothing);
    expect(find.text('the library'), findsOneWidget);
  });

  testWidgets('a load is said whatever chat runs on', (tester) async {
    await show(
      tester,
      status: 'Initializing model...',
      phase: KoboldPhase.starting,
      chat: BackendType.openRouter,
    );

    expect(find.text('Initializing model...'), findsOneWidget);
  });

  testWidgets('nothing on the status line: no bar', (tester) async {
    await show(
      tester,
      status: '',
      phase: KoboldPhase.stopped,
      chat: BackendType.kobold,
    );

    expect(find.byType(KoboldStatusBar), findsNothing);
    expect(find.text('the library'), findsOneWidget);
  });

  // The home page is too heavy to pump whole; its three views (chats,
  // stories, Waifu Coder) all wrap through this one method.
  test('the home page puts its content in it', () {
    final chrome = File(
      'lib/ui/pages/home/home_page_chrome.dart',
    ).readAsStringSync();

    expect(chrome, contains('KoboldHomeStatus(child: content)'));
  });
}
