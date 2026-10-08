// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A kept "no" must not switch native tool calls off for good. It is kept with
// the engine and app it was given under, and when either changes it is asked
// again once, so an engine or chat-template fix is picked up; a kept "yes"
// stays. The KoboldCpp version counts for the local engine; the app version
// counts for every backend. A restart is a new settings object, probe and
// tester over the same preferences.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_support_tester.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage/settings/tool_verdict_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/local_model_key.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/chat_db_teardown.dart';

const _model = 'KoboldCPP|||gemma.gguf#100';

const _calls = LlmToolResponse(
  calls: [
    LlmToolCall(name: 'report_ping', arguments: {'ok': true}),
  ],
  text: '',
);
const _prose = LlmToolResponse(calls: [], text: 'Sure, here you go.');

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// One run of the app over the preferences every run shares, on the engine
/// and app versions [stamp] says.
class _Run {
  _Run._(this.store, this.probe, this.tester, this.asked);

  final ToolVerdictSettings store;
  final ToolTransportProbe probe;
  final ToolSupportTester tester;
  final List<String> asked;

  static Future<_Run> open({
    required String stamp,
    LlmToolResponse Function()? reply,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final store = ToolVerdictSettings()
      ..initializeBase(prefs, () {})
      ..load();
    final probe = ToolTransportProbe()
      ..store = store
      ..stampFor = (_) => stamp;
    final asked = <String>[];
    final tester = ToolSupportTester(
      probe: probe,
      fireToolEval: (_, _) async {
        asked.add('ping');
        return (reply ?? () => _calls)();
      },
      getBackendIdentity: () => _model,
      isBackendReady: () => true,
      isBusy: () => false,
      onNotify: () {},
    );
    return _Run._(store, probe, tester, asked);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a kept answer carries what it was given under', () {
    test(
      'a "no" keeps its stamp and a "yes" keeps none, across a restart',
      () async {
        final first = await _Run.open(stamp: '1.0.0|1.117.1');
        first.store.remember('no model', false, stamp: '1.0.0|1.117.1');
        first.store.remember('yes model', true);

        final again = await _Run.open(stamp: '1.0.0|1.117.1');
        expect(again.store.verdictFor('no model'), isFalse);
        expect(again.store.stampFor('no model'), '1.0.0|1.117.1');
        expect(again.store.verdictFor('yes model'), isTrue);
        expect(again.store.stampFor('yes model'), isNull);
      },
    );

    test(
      'an answer kept before stamps existed is a "no" of unknown stamp',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          ToolVerdictSettings().k('tool_verdicts'),
          '{"old no": false, "old yes": true}',
        );
        final run = await _Run.open(stamp: '1.0.0|1.117.1');
        expect(run.store.verdictFor('old no'), isFalse);
        expect(run.store.stampFor('old no'), '');
        expect(run.store.verdictFor('old yes'), isTrue);
      },
    );
  });

  group('a kept "no" is asked again once when the engine or app changes', () {
    test('the same engine and app: it stands', () async {
      final first = await _Run.open(stamp: '1.0.0|1.117.1');
      first.probe.markXmlOnly(_model);

      final again = await _Run.open(stamp: '1.0.0|1.117.1');
      expect(again.probe.supportFor(_model), ToolCallSupport.unsupported);
      expect(again.probe.isXmlOnly(_model), isTrue);
      again.tester.onBackendMaybeChanged();
      await _settle();
      expect(again.asked, isEmpty);
    });

    test('another KoboldCpp: it is unknown again, tools are tried, and the '
        'test asks once', () async {
      final first = await _Run.open(stamp: '1.0.0|1.117.1');
      first.probe.markXmlOnly(_model);

      final again = await _Run.open(
        stamp: '1.0.0|1.122.1',
        reply: () => _prose,
      );
      expect(again.probe.supportFor(_model), ToolCallSupport.untested);
      expect(
        again.probe.isXmlOnly(_model),
        isFalse,
        reason: 'the passes try tools again',
      );
      again.tester.onBackendMaybeChanged();
      await _settle();
      expect(again.asked, ['ping']);

      // It is still a "no", and now it is a "no" under this engine.
      expect(again.probe.supportFor(_model), ToolCallSupport.unsupported);
      final third = await _Run.open(stamp: '1.0.0|1.122.1');
      expect(third.probe.supportFor(_model), ToolCallSupport.unsupported);
      third.tester.onBackendMaybeChanged();
      await _settle();
      expect(third.asked, isEmpty);
    });

    test('a fix is picked up: the second ask finds tool calls', () async {
      final first = await _Run.open(stamp: '1.0.0|1.117.1');
      first.probe.markXmlOnly(_model);

      final fixed = await _Run.open(stamp: '1.0.0|1.122.1');
      fixed.tester.onBackendMaybeChanged();
      await _settle();
      expect(fixed.probe.supportFor(_model), ToolCallSupport.supported);
      expect(
        (await _Run.open(stamp: '1.0.0|1.122.1')).store.verdictFor(_model),
        isTrue,
      );
    });

    test('another app version: asked again, for any backend', () async {
      final first = await _Run.open(stamp: '1.0.0|');
      first.probe.markXmlOnly('Remote API|https://x/v1|some/model|');

      final again = await _Run.open(stamp: '1.1.0|');
      expect(
        again.probe.supportFor('Remote API|https://x/v1|some/model|'),
        ToolCallSupport.untested,
      );
    });

    test(
      'an engine version that is not known yet does not unsettle it',
      () async {
        final first = await _Run.open(stamp: '1.0.0|1.117.1');
        first.probe.markXmlOnly(_model);

        // Before the engine has been looked at, only the app is known.
        final early = await _Run.open(stamp: '1.0.0|');
        expect(early.probe.supportFor(_model), ToolCallSupport.unsupported);
      },
    );

    test('a "yes" stays, whatever changed', () async {
      final first = await _Run.open(stamp: '1.0.0|1.117.1');
      first.probe.markSupported(_model);

      final again = await _Run.open(stamp: '2.0.0|1.200.0');
      expect(again.probe.supportFor(_model), ToolCallSupport.supported);
      again.tester.onBackendMaybeChanged();
      await _settle();
      expect(again.asked, isEmpty);
    });
  });

  group('the chat service reads the engine from the engine it runs', () {
    late Directory dir;
    late AppDatabase db;
    late StorageService storage;
    late KoboldService kobold;
    late LLMProvider provider;
    late ChatService chat;
    late _Manager manager;
    late _Answering answering;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fpai stale no');
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? dir.path
                : null,
          );
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      db = AppDatabase.forTesting();
      storage = StorageService();
      await storage.initialized;
      kobold = KoboldService(
        storage,
        systemRoleProbe: SystemRoleProbe(retryBackoff: Duration.zero),
      )..setBaseUrl('http://127.0.0.1:1');
      manager = _Manager(storage);
      provider = LLMProvider(
        kobold,
        OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
        storage,
        manager,
      );
      answering = _Answering();
      chat =
          ChatService(
              kobold,
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setLLMProvider(provider)
            ..testLlmServiceOverride = answering;
    });

    tearDown(() async {
      await disposeChatThenCloseDb(chat, db);
      provider.dispose();
      kobold.dispose();
      await dir.delete(recursive: true);
    });

    String keyOf(File file) => 'Scripted|||${localModelKey(file.path)}';

    test(
      'a local "no" given under another KoboldCpp is asked again, once',
      () async {
        chat.testIsLocalOverride = true;
        manager.version = '1.122.1';
        final file = File(p.join(dir.path, 'gemma.gguf'))
          ..writeAsBytesSync(List.filled(2048, 1));
        storage.toolVerdictSettings.remember(
          keyOf(file),
          false,
          stamp: '$appVersion|1.117.1',
        );
        await storage.backendSettings.setLastUsedModelPath(file.path);
        await _settle();

        expect(answering.asked, 1, reason: 'the engine changed: asked once');
        expect(chat.toolCallSupport, ToolCallSupport.supported);
      },
    );

    test('a local "no" given under this KoboldCpp stands', () async {
      chat.testIsLocalOverride = true;
      manager.version = '1.122.1';
      final file = File(p.join(dir.path, 'gemma.gguf'))
        ..writeAsBytesSync(List.filled(2048, 1));
      storage.toolVerdictSettings.remember(
        keyOf(file),
        false,
        stamp: '$appVersion|1.122.1',
      );
      await storage.backendSettings.setLastUsedModelPath(file.path);
      await _settle();

      expect(chat.toolCallSupport, ToolCallSupport.unsupported);
      expect(answering.asked, 0);
    });

    test(
      'a remote "no" given under another app version is asked again',
      () async {
        chat.testIsLocalOverride = false;
        await storage.backendSettings.setRemoteModelName('some/model');
        final key = chat.debugEvalBackendIdentity;
        storage.toolVerdictSettings.remember(key, false, stamp: '0.0.1|');
        expect(chat.toolCallSupport, ToolCallSupport.untested);

        storage.toolVerdictSettings.remember(key, false, stamp: '$appVersion|');
        expect(chat.toolCallSupport, ToolCallSupport.unsupported);
      },
    );
  });
}

/// The installed engine's version, as the chat service is told it.
class _Manager extends BackendManager {
  _Manager(super.storage);

  String? version;

  @override
  String? get localVersion => version;
}

class _Answering extends LLMService {
  int asked = 0;

  @override
  Stream<String> generateStream(GenerationParams params) =>
      const Stream.empty();

  @override
  bool get isReady => true;

  @override
  String get backendName => 'Scripted';

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    asked++;
    return _calls;
  }
}
