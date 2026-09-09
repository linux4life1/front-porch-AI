// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

class _CaptureLlm extends LLMService {
  GenerationParams? last;

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    last = params;
    return const LlmToolResponse(calls: [], text: '');
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'Capture';
}

void main() {
  test('first mutation step forces a tool; chat and later steps do not', () {
    expect(
      waifuForceFirstTool(
        step: 0,
        speechOnly: false,
        mutationRequired: true,
        mutationSucceeded: false,
      ),
      isTrue,
    );
    expect(
      waifuForceFirstTool(
        step: 1,
        speechOnly: false,
        mutationRequired: true,
        mutationSucceeded: false,
      ),
      isFalse,
    );
    expect(
      waifuForceFirstTool(
        step: 0,
        speechOnly: true,
        mutationRequired: true,
        mutationSucceeded: false,
      ),
      isFalse,
    );
    expect(
      waifuForceFirstTool(
        step: 0,
        speechOnly: false,
        mutationRequired: false,
        mutationSucceeded: false,
      ),
      isFalse,
    );
    expect(
      waifuForceFirstTool(
        step: 0,
        speechOnly: false,
        mutationRequired: true,
        mutationSucceeded: true,
      ),
      isFalse,
    );
  });

  test('implement send forces a tool on the first generate only', () async {
    final root = await Directory.systemTemp.createTemp('waifu_first_tool_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'PageTurn.swift', 'contents': 'import Metal\n'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Mesh is on disk.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await WaifuHarness(
      session: session,
      llm: llm,
    ).send('implement a page-turn animation in Swift');
    expect(llm.calls, isNotEmpty);
    expect(llm.calls.first.forceTool, isTrue);
    expect(llm.calls.first.tools, isNotEmpty);
    expect(llm.calls.last.forceTool, isFalse);
  });

  test('production door sends required and turns thinking off', () async {
    final cap = _CaptureLlm();
    await LlmServiceWaifuLlm(() => cap).generate(
      systemPrompt: 's',
      prompt: 'p',
      tools: const [
        {
          'type': 'function',
          'function': {'name': 'write'},
        },
      ],
      forceTool: true,
    );
    expect(cap.last, isNotNull);
    expect(cap.last!.toolChoice, kToolChoiceRequired);
    expect(cap.last!.reasoningMaxTokens, 0);

    await LlmServiceWaifuLlm(() => cap).generate(
      systemPrompt: 's',
      prompt: 'p',
      tools: const [
        {
          'type': 'function',
          'function': {'name': 'write'},
        },
      ],
    );
    expect(cap.last!.toolChoice, isNull);
    expect(cap.last!.reasoningMaxTokens, isNull);
  });

  test('a plain hello does not force a tool', () async {
    final root = await Directory.systemTemp.createTemp('waifu_hello_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [], text: 'Hey. What are we building?'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await WaifuHarness(session: session, llm: llm).send('hey');
    expect(llm.calls, hasLength(1));
    expect(llm.calls.single.forceTool, isFalse);
  });
}
