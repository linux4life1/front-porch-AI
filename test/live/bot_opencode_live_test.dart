// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

@Tags(['kobold_live'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

import 'live_engine.dart';

void main() {
  final binary = Platform.environment['FPAI_BOT_OPENCODE_BIN'];
  test(
    'managed OpenCode uses the Bot’s voice in a disposable Plan project',
    () async {
      HttpOverrides.global = null;
      final root = await Directory.systemTemp.createTemp('bot_opencode_');
      final project = await Directory('${root.path}/project').create();
      const original = '# Orchard notes\n';
      final readme = await File(
        '${project.path}/README.md',
      ).writeAsString(original);
      await File('${project.path}/.waifu/todos.json').create(recursive: true);
      await File(
        '${project.path}/.waifu/todos.json',
      ).writeAsString('{"items":[]}');

      final manager = OpenCodeManager(rootPath: '${root.path}/support');
      await manager.closet.ensureLayout();
      await File(binary!).copy(manager.closet.binaryPath);
      await Process.run('chmod', ['+x', manager.closet.binaryPath]);

      final port = await freePort();
      final engine = await LiveEngine.start(
        await copyEngineInto(Directory('${root.path}/engine')),
        [
          '--model',
          liveEngineModel,
          '--port',
          '$port',
          '--host',
          '127.0.0.1',
          '--usecpu',
          '--threads',
          '4',
          '--contextsize',
          '8192',
          '--quiet',
        ],
      );
      addTearDown(() async {
        await manager.stop();
        manager.dispose();
        engine.process.kill();
        await engine.process.exitCode;
        final log = File(manager.closet.serveLogPath);
        final logCopy = Platform.environment['FPAI_BOT_OPENCODE_LOG'];
        if (logCopy != null && await log.exists()) await log.copy(logCopy);
        await root.delete(recursive: true);
      });
      await waitForLiveModel(port);

      final card = CharacterCard(
        name: 'Juniper',
        description: 'A concise documentation coach.',
        scenario: 'Help the user revise their project README headings.',
      )..setBotCard(true, 'Offer one improved heading and a short reason.');
      const model = 'bot-test-local';
      OpenCodeClient clientOf(Uri base, String directory) => OpenCodeClient(
        baseUri: base,
        directory: directory,
        voiceSettle: const Duration(seconds: 5),
      );

      Future<OpenCodeSessionInfo> sit([String? previous]) =>
          waifuOpenCodeSitDown(
            manager: manager,
            clientOf: clientOf,
            coworker: card,
            folderRoot: project.path,
            pathMode: WaifuPathMode.folderJail,
            mode: WaifuMode.plan,
            backend: OpenCodePorchBackend(
              baseUrl: 'http://127.0.0.1:$port/v1',
              apiKey: 'fixture-only',
              modelId: model,
            ),
            resumeSessionId: previous,
          );

      final session = await sit();
      final config =
          jsonDecode(await File(manager.closet.configFilePath).readAsString())
              as Map;
      final agents = config['agent'] as Map;
      expect(config['default_agent'], 'plan');
      expect(agents['plan']['prompt'], contains(card.scenario));
      expect(agents['plan']['permission']['edit'], 'deny');
      expect(agents['waifu']['permission']['edit'], 'ask');
      expect(manager.baseUri.host, '127.0.0.1');

      final client = clientOf(manager.baseUri, project.path);
      final reply = _PlanReply(client);
      await client
          .promptAndPump(
            sessionId: session.id,
            parts: openCodePromptParts(
              text:
                  'Plan a small README heading change. The current '
                  'heading is Orchard notes. Suggest one heading and address me directly. '
                  'Do not edit any files.',
            ),
            sink: reply,
            agent: 'plan',
            providerID: kOpenCodePorchProvider,
            modelID: model,
          )
          .timeout(const Duration(minutes: 3));
      expect(reply.errors, isEmpty);
      expect(reply.text.toString().trim(), isNotEmpty);
      expect(await readme.readAsString(), original);
      print('OpenCode Plan reply: ${reply.text}');
      expect((await sit(session.id)).id, session.id);
    },
    skip: binary == null
        ? 'Set FPAI_BOT_OPENCODE_BIN to the pinned Linux release.'
        : liveEngineSkip,
    timeout: const Timeout(Duration(minutes: 7)),
  );
}

class _PlanReply extends OpenCodeEventSink {
  _PlanReply(this.client);

  final OpenCodeClient client;
  final text = StringBuffer();
  final errors = <String>[];

  @override
  void onTextDelta(
    String delta, {
    String messageId = '',
    bool thinking = false,
  }) {
    if (!thinking) text.write(delta);
  }

  @override
  void onError(String message) => errors.add(message);

  @override
  void onIdle() {}

  @override
  void onPermissionAsk(OpenCodePermissionAsked ask) {
    final canRead =
        ask.permission == 'read' &&
        ask.patterns.every(
          (path) =>
              path.endsWith('/.waifu/todos.json') ||
              path.endsWith('/README.md'),
        );
    unawaited(
      client.respondPermission(
        sessionId: ask.sessionId,
        permissionId: ask.permissionId,
        response: canRead ? 'once' : 'reject',
      ),
    );
  }

  @override
  void onTodo(List<OpenCodeTodoItem> todos) {}

  @override
  void onTokens({required int promptTokens, required int outputTokens}) {}

  @override
  void onTool({
    required String name,
    required String detail,
    required bool ok,
    bool pending = false,
    String callId = '',
  }) {}
}
