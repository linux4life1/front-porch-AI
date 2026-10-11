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

// Two teardown/staleness contracts still pinned on their call sites, because
// neither has a seam a behavioural test may use:
//  - STT needs the real microphone recorder and Whisper; the only SttService
//    double would plant the transcript.
//  - Stoop browse would need a fake Stoop server or canned JSON, which the
//    no-stub rule forbids for new Stoop pins (CLAUDE.md "No stub tests").
// The other contracts that lived here are now driven for real:
// home/home_listener_teardown_test.dart, chat_impersonate_teardown_test.dart
// and import_lorebook_world_name_gate_test.dart.

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
  test('STT does not write the input controller after the ChatPage is '
      'gone', () {
    // Whisper keeps transcribing after the page pops; the result is written
    // into _controller, which dispose() already disposed.
    final src = _read('lib/ui/pages/chat_page.input_actions.dart');
    final stt = _between(
      src,
      'stopRecordingAndTranscribe();',
      'if (text != null',
      what: 'the STT transcribe branch',
    );
    expect(
      stt,
      contains('if (!mounted) return;'),
      reason:
          'the transcription lands on a disposed controller when the '
          'user leaves the chat while Whisper is still running',
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
      reason:
          'two overlapping _loadAlls race and the slower response wins, '
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
      reason:
          'an in-flight page append lands on top of a newer filter, '
          'mixing cards into the grid and skipping a page',
    );
  });
}
