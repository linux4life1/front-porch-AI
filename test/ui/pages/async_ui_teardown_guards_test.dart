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

// Four teardown/staleness contracts on pages that outlive their own async
// work. Each subject is a private State behind the main.dart provider graph
// (HomePage needs the DB-backed CharacterRepository, ChatPage needs the whole
// ChatService), so there is no unit seam to pump — these read the call sites
// directly, the same way home_tap_session_identity_test and
// chaos_global_toggle_test do. They catch the exact regression (the guard
// being deleted), not the general class.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

String _between(String src, String start, String end, {required String what}) {
  final a = src.indexOf(start);
  expect(a, isNot(-1), reason: 'could not find "$start" — $what moved');
  final b = src.indexOf(end, a);
  expect(b, isNot(-1), reason: 'could not find "$end" after "$start"');
  return src.substring(a, b);
}

void main() {
  test('HomePage unsubscribes from every notifier it listened to', () {
    // MainLayout swaps HomePage out of the tree on each sidebar navigation
    // (a plain _pages[index] child, not an IndexedStack), so the State is
    // disposed and recreated every time. KoboldService and
    // CharacterRepository are app-scoped singletons: a listener that is
    // never removed keeps a dead _HomePageState (and its caches) alive for
    // the rest of the run, once per Home visit.
    final src = _read('lib/ui/pages/home_page.dart');
    final dispose = _between(
      src,
      'void dispose() {',
      'super.dispose();',
      what: 'the HomePage dispose',
    );
    for (final cb in [
      '_onKoboldUpdate',
      '_onCharactersChanged',
      '_onAppStateChanged',
    ]) {
      expect(
        dispose,
        contains('removeListener($cb)'),
        reason: 'HomePage.dispose no longer removes $cb — the listener '
            'accumulates on an app-scoped notifier on every Home visit',
      );
    }
    expect(
      dispose.contains('Provider.of'),
      isFalse,
      reason: 'a Provider lookup in dispose runs against a defunct element '
          '(it asserts in debug) — hold the notifier in a field instead',
    );
  });

  test('Impersonate and STT do not write the input controller after the '
      'ChatPage is gone', () {
    // ChatService is app-scoped and impersonateUser keeps streaming after the
    // page pops; the token callback writes _controller, which dispose()
    // already disposed.
    final src = _read('lib/ui/pages/chat_page.input_actions.dart');
    final onToken = _between(
      src,
      'onToken: (accumulated) {',
      '_controller.text = accumulated;',
      what: 'the impersonate token callback',
    );
    expect(
      onToken,
      contains('if (!mounted) return;'),
      reason: 'the impersonate token callback writes a disposed controller '
          'when the user leaves the chat mid-stream',
    );

    final stt = _between(
      src,
      'stopRecordingAndTranscribe();',
      'if (text != null',
      what: 'the STT transcribe branch',
    );
    expect(
      stt,
      contains('if (!mounted) return;'),
      reason: 'the transcription lands on a disposed controller when the '
          'user leaves the chat while Whisper is still running',
    );
  });

  test('Import Lorebook rebuilds its nav bar when the World name changes', () {
    // _canProceed reads _worldNameCtrl.text, and it is only consulted while
    // building the nav buttons — without a listener, clearing the name leaves
    // the Import button enabled and creates a World named "".
    final src = _read('lib/ui/pages/import_lorebook_page.dart');
    expect(
      src,
      contains('_worldNameCtrl.addListener('),
      reason: 'nothing rebuilds the Import button as the World name is typed '
          'or cleared, so an empty name still imports',
    );
    expect(
      src,
      contains('_worldNameCtrl.removeListener('),
      reason: 'the listener must come off before the controller is disposed',
    );
  });

  test('Stoop browse drops responses from a superseded filter', () {
    // A page load in flight when the user taps another type chip used to
    // append its cards on top of the new filter's grid and desync _page.
    final src = _read('lib/ui/pages/repository/stoop_browse_view.dart');
    final loadAll = _between(
      src,
      'Future<void> _loadAll() async {',
      'Future<void> _loadMore() async {',
      what: '_loadAll',
    );
    expect(
      loadAll,
      contains('++_reqGen'),
      reason: 'a full reload must claim a new request generation',
    );
    expect(
      loadAll,
      contains('gen != _reqGen'),
      reason: 'two overlapping _loadAlls race and the slower response wins, '
          'leaving the grid showing a filter the chips no longer show',
    );
    final loadMore = _between(
      src,
      'Future<void> _loadMore() async {',
      'void _onScroll() {',
      what: '_loadMore',
    );
    expect(
      loadMore,
      contains('gen != _reqGen'),
      reason: 'an in-flight page append lands on top of a newer filter, '
          'mixing cards into the grid and skipping a page',
    );
  });
}
