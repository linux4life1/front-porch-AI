// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The phone picks chat's preset while KoboldCpp runs: the new preset loads
// in place, which takes as long as the model takes to load (up to fifteen
// minutes for a big one). The request must not be held for that, and a
// reload that fails must not turn the pick, which is already stored, into
// an error: the desktop picker and the context setter do neither.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

class _Kobold extends FakeKoboldService {
  @override
  bool get isProcessRunning => true;
}

class _Llm extends FakeLLMProvider {
  final kobold = _Kobold();

  /// Completes when the test lets the model "finish loading".
  final loaded = Completer<void>();
  int reloads = 0;
  bool fails = false;

  @override
  KoboldService get koboldService => kobold;

  @override
  Future<void> reloadChatKobold() {
    reloads++;
    return fails
        ? Future<void>.error(StateError('KoboldCpp did not answer'))
        : loaded.future;
  }
}

void main() {
  late Directory dir;
  late _Storage storage;
  late _Llm llm;
  late BackendFacade facade;
  late String preset;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fpai chat preset');
    preset = p.join(dir.path, 'Long chats.kcpps');
    File(preset).writeAsStringSync(jsonEncode({'contextsize': 32768}));
    storage = _Storage(dir);
    llm = _Llm();
    facade = BackendFacade(llm, storage, FakeModelManager());
  });

  tearDown(() {
    if (!llm.loaded.isCompleted) llm.loaded.complete();
    dir.deleteSync(recursive: true);
  });

  test('the pick is answered while the model is still loading', () async {
    final answered = facade.setChatPreset(preset);

    expect(
      await answered.timeout(const Duration(seconds: 2)),
      isTrue,
      reason: 'held for the whole load, the request would sit here',
    );
    expect(storage.backendSettings.activeKcppsPath, preset);
    expect(llm.reloads, 1, reason: 'the reload was asked for');
    expect(llm.loaded.isCompleted, isFalse, reason: 'and is still going');
  });

  test(
    'a reload that fails does not turn the stored pick into an error',
    () async {
      llm.fails = true;

      expect(await facade.setChatPreset(preset), isTrue);
      // Let the failed reload surface where it would be seen.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(storage.backendSettings.activeKcppsPath, preset);
      expect(llm.reloads, 1);
    },
  );
}
