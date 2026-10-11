// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/chargen/chat_grounding.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

const _secret = 'secret planning the user must never see';

// A description that ends in a backslash: in JSON text the value closes with
// `\\"`, which the old "previous char is not a backslash" scan read as an
// escaped quote, so the string never closed.
const _description = r'She keeps her notes under C:\';
const _personality = 'Guarded at first.\nWarm once she trusts you.';

/// Streams each reply in small chunks behind a capitalised `<Think>` block,
/// the way a hot reasoning model does.
class _ThinkingLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final reply = '<Think>$_secret</Think>${_answer(params.prompt)}';
    for (var i = 0; i < reply.length; i += 7) {
      yield reply.substring(i, i + 7 > reply.length ? reply.length : i + 7);
    }
  }

  String _answer(String p) {
    if (p.contains('rewrite these three fields')) {
      // Literal newline inside the personality string, as models emit it.
      return '{"description": ${jsonEncode(_description)},\n'
          '"personality": "$_personality",\n'
          '"scenario": "A quiet bar after hours where {{user}} walks in."}';
    }
    return 'I talk like the bar taught me: fast, warm, and armored.';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'thinking-test';
}

void main() {
  test('enhance progress never shows a capitalised <Think> block, and a value '
      'ending in a backslash survives the newline repair', () async {
    final previews = <String>[];
    final result = await CharacterGenService(_ThinkingLlm()).enhanceCharacter(
      source: CharacterCard(
        name: 'Nina',
        description: 'Original description.',
        personality: 'Original personality.',
        scenario: 'Original scenario.',
        firstMessage: 'Original first message.',
      ),
      selection: const EnhanceSelection(
        description: true,
        personality: true,
        exampleDialogue: false,
      ),
      chatGrounding: 'User: hello Nina\nNina: well well',
      onProgress: previews.add,
    );

    expect(previews, isNotEmpty);
    for (final p in previews) {
      expect(p, isNot(contains(_secret)));
      expect(p.toLowerCase(), isNot(contains('<think>')));
    }
    expect(result, isNotNull);
    expect(result!.description, _description);
    expect(result.personality, _personality);
  });

  group('JsonSanitizer string escapes', () {
    test('a value ending in an escaped backslash closes its string', () {
      const raw = '{"a": "C:\\\\",\n"b": "one\ntwo"}';
      expect(json.decode(JsonSanitizer.escapeControlCharsInStrings(raw)), {
        'a': r'C:\',
        'b': 'one\ntwo',
      });
      expect(JsonSanitizer.tryParse(raw), {'a': r'C:\', 'b': 'one\ntwo'});
    });

    test('hasCompleteObject ignores braces in strings and {{macros}}', () {
      expect(JsonSanitizer.hasCompleteObject('{"a": "C:\\\\"}'), isTrue);
      expect(JsonSanitizer.hasCompleteObject('{"a": "{{char}} }"'), isFalse);
      expect(JsonSanitizer.hasCompleteObject('{"a": "x"} trailing'), isTrue);
      expect(JsonSanitizer.hasCompleteObject('text {"a": 1}'), isFalse);
    });
  });
}
