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

// PROVABILITY NET for the chat_service_generation.dart split
// (docs-less design map: scratchpad/maps/chat_service_generation.map.md).
// This file is a behavior-pinning net, not a feature test: every assertion
// here targets a specific line range the split map calls out as an
// "uncovered internal" of _generateResponse's stream/finalize machinery —
// the exact code the future decomposition into _consumeGenerationStream /
// _finalizeGenerationTurn is most likely to shift subtly. It deliberately
// does NOT re-test what regen_chip_attach_test.dart already covers (chip
// attach on a swipe, backend-reached, settling-flag lifecycle) — the harness
// pattern (real ChatService + testLlmServiceOverride against the E2E
// FakeBackendServer) is copied from that file so both suites drive the SAME
// code path the same way, but the assertions below are new surfaces:
//
//   1. think-aware stop-sequence scanning (chat_service_generation.dart
//      ~1372-1398): a stop-sequence-looking line INSIDE an open <think>
//      block must not be cut by the mid-stream trim scan — the scan is
//      supposed to be blind to think-internal text until the block closes.
//   2. unclosed-<think> salvage (~1612-1622): a reply whose stream ends
//      still inside an open <think> (the backend's own stop sequence cut it
//      off) gets a synthetic closing tag appended so the thought survives as
//      a well-formed, renderable block instead of persisting broken forever.
//   3. the output-sanitizer wipe-guard (~1630-1644): a sanitizer rule that
//      would reduce a non-empty reply to nothing must be overridden — the
//      original text survives rather than the user losing the whole reply.
//   4. the catch-block error-message mapping (~1902-1928): a raw backend
//      exception must be translated to its friendly copy before it becomes
//      a System chat message, and the turn must fully settle afterward (no
//      stuck busy/composer-locked state).
//
// Realism and Needs are OFF on the test character throughout: these pins are
// about transport/stream mechanics, not scoring, and turning them off keeps
// each turn to exactly one backend call (no eval traffic to model), per the
// CLAUDE.md instruction to leave realism scoring behavior alone here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

/// Resets the mocked SharedPreferences store fresh for one test. Realism is
/// forced off at the global-default layer too (belt-and-braces alongside the
/// per-character flag below) so a turn never fires an eval call these tests
/// don't model.
void _resetPrefs() {
  SharedPreferences.setMockInitialValues({
    'update_auto_check': false,
    'realism_default': false,
  });
}

/// A ChatService wired to [llm] via the same testLlmServiceOverride seam
/// regen_chip_attach_test.dart uses, with a fresh character whose realism
/// and needs simulation are both explicitly off. Returned as a record so
/// each test can reach the storage service too (needed for the sanitizer
/// pin) without a bespoke holder class.
Future<({AppDatabase db, ChatService chat, StorageService storage})>
_buildRealismOffChat(OpenRouterService llm) async {
  final db = AppDatabase.forTesting();
  final storage = StorageService();
  final personas = UserPersonaService(db);
  final worlds = WorldRepository(storage, db);
  final chat = ChatService(KoboldService(storage), personas, storage, worlds)
    ..setDatabase(db)
    ..testLlmServiceOverride = llm;
  await storage.initialized;
  // Content-side `<think>` is peeled unless wrap is on (f2cf39e7). These
  // pins are the ChatService stop-scan / salvage, which only see tags
  // that ingest kept.
  await storage.backendSettings.setReasoningEnabled(true);
  await chat.setActiveCharacter(
    CharacterCard(
      name: 'Jennifer',
      description: 'Exists only inside the generation-stream unit test.',
      firstMessage: 'Welcome to the porch.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'char-genstream',
  );
  return (db: db, chat: chat, storage: storage);
}

/// A minimal loopback OpenAI-compatible server that ALWAYS fails the chat
/// completion with a controlled error body — used only by the error-mapping
/// pin, which needs to choose the raw failure text precisely (to land inside
/// one specific friendly-mapping branch) rather than the fixed wording
/// FakeBackendServer's failure injection hard-codes.
Future<HttpServer> _startAlwaysFailingBackend(String rawMessage) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    if (req.uri.path == '/v1/chat/completions') {
      req.response.statusCode = HttpStatus.internalServerError;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'error': {'message': rawMessage},
        }),
      );
    } else {
      req.response.statusCode = HttpStatus.notFound;
    }
    await req.response.close();
  });
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('a stop-sequence-looking line inside an open <think> block survives '
      'the mid-stream trim scan', () async {
    HttpOverrides.global = null;
    _resetPrefs();
    final backend = await FakeBackendServer.start(
      // Three SSE chunks so the open tag, the stop-sequence-looking line,
      // and the close all land in SEPARATE token iterations of the stream
      // loop — the scenario the think-aware guard exists for. The
      // character's own name ("Jennifer") is in the stop list for every
      // 1:1 turn (buildPrioritizedStops adds "\n<CharacterName>:"), so
      // "\nJennifer:" forming across the first two chunks is a genuine
      // stop-sequence match — it just must not be acted on while inside
      // an unclosed <think>.
      replyPieces: [
        '<think>\n',
        'Jennifer: quick note - remember to smile.\n',
        '</think>\nHey there! Glad you stopped by the porch.',
      ],
    );
    final llm = OpenRouterService(
      apiUrl: '${backend.baseUrl}/v1',
      modelName: 'smoke-model',
    );
    final h = await _buildRealismOffChat(llm);
    addTearDown(() async {
      h.chat.dispose();
      await backend.close();
      await h.db.close();
    });

    await h.chat.sendMessage('Hi Jennifer, how are you tonight?');

    final msg = h.chat.messages.last;
    expect(msg.isUser, isFalse);
    expect(
      msg.text,
      contains('Jennifer: quick note - remember to smile.'),
      reason:
          'the stop-sequence-looking line inside the open <think> block '
          'must survive — trimming it here is the pre-fix bug the '
          'think-aware scan guard exists to prevent',
    );
    expect(
      msg.thinkingContent,
      contains('Jennifer: quick note'),
      reason: 'the thought must still be extractable for the UI panel',
    );
    expect(
      msg.displayText,
      'Hey there! Glad you stopped by the porch.',
      reason:
          'the visible bubble must show only the post-</think> reply, '
          'untouched by the stop scan that correctly fired AFTER the close',
    );
    expect(h.chat.isGenerating, isFalse);
    expect(h.chat.isSettlingTurn, isFalse);
    expect(
      backend.chatRequests,
      1,
      reason: 'exactly one real generation call, no eval traffic',
    );
    expect(backend.unexpectedPaths, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('a reply that ends still inside an open <think> gets the closing tag '
      'salvaged', () async {
    HttpOverrides.global = null;
    _resetPrefs();
    final backend = await FakeBackendServer.start(
      // No </think> anywhere — models the backend's OWN stop sequence
      // cutting the stream off mid-thought (comment at ~1612 in
      // chat_service_generation.dart). mode == normal, so the Continue/
      // call-mode strip (_stripThinkBlocks) never runs; the salvage at
      // ~1617-1622 is the only thing standing between this and a message
      // whose raw text is permanently an unbalanced <think>.
      replyPieces: [
        '<think>\n',
        'Wondering how to phrase this, but the connection drops here...',
      ],
    );
    final llm = OpenRouterService(
      apiUrl: '${backend.baseUrl}/v1',
      modelName: 'smoke-model',
    );
    final h = await _buildRealismOffChat(llm);
    addTearDown(() async {
      h.chat.dispose();
      await backend.close();
      await h.db.close();
    });

    await h.chat.sendMessage('Are you still with me?');

    final msg = h.chat.messages.last;
    expect(msg.isUser, isFalse);
    expect(
      msg.text.trim(),
      endsWith('</think>'),
      reason:
          'the persisted raw text must be balanced — an unclosed <think> '
          'left as-is would strand the message empty on every future '
          'render/reload',
    );
    expect(
      '<think>'.allMatches(msg.text.toLowerCase()).length,
      1,
      reason: 'salvage must add exactly one closing tag, not double it up',
    );
    expect('</think>'.allMatches(msg.text.toLowerCase()).length, 1);
    expect(
      msg.thinkingContent,
      contains('connection drops here'),
      reason: 'the stranded thought must still render as the collapsible',
    );
    expect(
      msg.displayText,
      isEmpty,
      reason: 'nothing followed the (now-closed) think block',
    );
    expect(h.chat.isGenerating, isFalse);
    expect(h.chat.isSettlingTurn, isFalse);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('an output-sanitizer rule that would wipe a non-empty reply keeps the '
      'original text', () async {
    HttpOverrides.global = null;
    _resetPrefs();
    final backend = await FakeBackendServer.start(
      replyPieces: ['The porch swing creaks softly in the evening breeze.'],
    );
    final llm = OpenRouterService(
      apiUrl: '${backend.baseUrl}/v1',
      modelName: 'smoke-model',
    );
    final h = await _buildRealismOffChat(llm);
    addTearDown(() async {
      h.chat.dispose();
      await backend.close();
      await h.db.close();
    });

    // A rule that matches the WHOLE printable reply and deletes it — the
    // "runaway rule" scenario the wipe-guard at chat_service_generation.dart
    // ~1633 exists to catch.
    await h.storage.generationSettings.setOutputSanitizerEnabled(true);
    await h.storage.generationSettings.setOutputSanitizerRules(const [
      OutputSanitizerRule(id: 0, find: r'\a+', replace: ''),
    ]);

    await h.chat.sendMessage('Tell me about the porch.');

    final msg = h.chat.messages.last;
    expect(msg.isUser, isFalse);
    expect(
      msg.text,
      'The porch swing creaks softly in the evening breeze.',
      reason:
          'a sanitizer rule that reduces the whole reply to nothing must '
          'be overridden — the user must never lose an entire reply to a '
          'runaway find/replace rule',
    );
    expect(h.chat.isGenerating, isFalse);
    expect(h.chat.isSettlingTurn, isFalse);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('a backend failure maps to its friendly message, not the raw exception, '
      'and the turn fully settles', () async {
    HttpOverrides.global = null;
    _resetPrefs();
    const rawFailure = 'Request timed out waiting for the model to respond.';
    final server = await _startAlwaysFailingBackend(rawFailure);
    final llm = OpenRouterService(
      apiUrl: 'http://127.0.0.1:${server.port}/v1',
      modelName: 'smoke-model',
    );
    final h = await _buildRealismOffChat(llm);
    addTearDown(() async {
      h.chat.dispose();
      await server.close(force: true);
      await h.db.close();
    });

    await h.chat.sendMessage('Hello? Anyone home?');

    final msg = h.chat.messages.last;
    expect(msg.sender, 'System');
    expect(
      msg.text,
      'Request timed out. The model may be too large or the server too '
      'slow.',
      reason:
          'the raw "API error: $rawFailure" text must be MAPPED to the '
          'friendly copy before it reaches the chat — a user with zero '
          'technical knowledge must be able to read this',
    );
    expect(msg.text, isNot(contains('API error')));
    expect(msg.text, isNot(contains('Exception')));
    expect(
      h.chat.isGenerating,
      isFalse,
      reason: 'a failed generation must not leave the send button dead',
    );
    expect(
      h.chat.isSettlingTurn,
      isFalse,
      reason:
          'a failed generation must fully release the settling hold — a '
          'latched flag here would wedge every later action',
    );
  }, timeout: const Timeout(Duration(minutes: 1)));
}
