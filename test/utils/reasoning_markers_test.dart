// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Bytes-only think-wrapper sniff. No model names. Proven against the
// NanoGPT Gemma dump (leading `thought`, no <think>) and the wrappers
// the industry actually emits.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/reasoning_stream_wrapper.dart';
import 'package:front_porch_ai/utils/reasoning_markers.dart';
import 'package:front_porch_ai/utils/think_tags.dart';

void main() {
  group('canonicalizeReasoning', () {
    test('plain prose is untouched', () {
      expect(canonicalizeReasoning('Hello there.'), 'Hello there.');
    });

    test('<think> identity is unchanged', () {
      const raw = '<think>plan</think>\n"Hi."';
      expect(canonicalizeReasoning(raw), raw);
    });

    test('Gemma 4 channel becomes <think>', () {
      const raw = '<|channel>thought\nThe user ran.\n<channel|>"Stay."';
      final out = canonicalizeReasoning(raw);
      expect(out, startsWith('<think>'));
      expect(out, contains('</think>'));
      expect(out, contains('"Stay."'));
      expect(out, isNot(contains('<|channel>')));
    });

    test('stripped Gemma leftover thought\\n still parses when closed', () {
      const raw = 'thought\nlong essay\n<channel|>"Spoken."';
      final out = canonicalizeReasoning(raw);
      expect(out, contains('<think>long essay\n</think>'));
      expect(out, contains('"Spoken."'));
    });

    test('harmony analysis channel becomes <think>', () {
      const raw = '<|channel|>analysis\nstep one\n<|channel|>final\nAnswer.';
      final out = canonicalizeReasoning(raw);
      expect(out, contains('<think>'));
      expect(out, contains('step one'));
      expect(out, contains('</think>'));
      expect(out, contains('Answer.'));
    });

    test('Kimi triangle think tags', () {
      expect(
        canonicalizeReasoning('◁think▷secret◁/think▷Hi.'),
        '<think>secret</think>\nHi.',
      );
    });

    test('<reasoning> and <thinking> both convert', () {
      expect(
        canonicalizeReasoning('<reasoning>a</reasoning>B'),
        '<think>a</think>\nB',
      );
      expect(
        canonicalizeReasoning('<thinking>a</thinking>B'),
        '<think>a</think>\nB',
      );
    });

    test('"I thought about it" is not a think block', () {
      const raw = 'I thought about it on the porch.';
      expect(canonicalizeReasoning(raw), raw);
      expect(stripThinkTags(raw), raw);
    });
  });

  group('ReasoningMarkerRewriter streaming', () {
    test('split Gemma open across tokens', () {
      final r = ReasoningMarkerRewriter();
      expect(r.push('<|chan'), '');
      final mid = r.push('nel>thought\nfoo');
      expect(mid, contains('<think>'));
      expect(mid, contains('foo'));
      final end = r.push('bar<channel|>hi');
      expect(end, contains('</think>'));
      expect(end, contains('hi'));
      expect(r.finish(), '');
    });

    test('ordinary prose is not delayed', () {
      final r = ReasoningMarkerRewriter();
      expect(r.push('Hel'), 'Hel');
      expect(r.push('lo'), 'lo');
    });

    test('keep:false drops the think body', () {
      final r = ReasoningMarkerRewriter(keep: false);
      expect(r.push('<|channel>thought\nessay<channel|>"Hi."'), '"Hi."');
    });
  });

  group('ReasoningIngest', () {
    test('content-side Gemma becomes a Thought chip + spoken body', () {
      final i = ReasoningIngest(wrap: true);
      final a = i.onContent('<|channel>thought\nessay\n');
      final b = i.onContent('<channel|>"Stay."');
      final c = i.finish();
      final all = '$a$b$c';
      expect(all, contains('<think>'));
      expect(all, contains('</think>'));
      expect(all, contains('"Stay."'));
      final msg = ChatMessage(text: all, sender: 'Nemu', isUser: false);
      expect(msg.thinkingContent, contains('essay'));
      expect(msg.displayText, '"Stay."');
    });

    test('reasoning_content still wraps as before', () {
      final i = ReasoningIngest(wrap: true);
      expect(i.onReasoning('abc'), '<think>abc');
      expect(i.onContent('ans'), '</think>\nans');
    });
  });

  // Nano-GPT hides the think channel of Kimi K2.6 thinking server-side
  // (`reasoning.exclude`) and, after a long think, leaves the tail of the
  // closing tag at the head of the content: three live captures opened
  // with `hin` + `k> To impress…`; chat showed `think>`. No `<` ever
  // reaches the app, so the fence sniff cannot see it.
  group('stripped close-tag tail at the head of a reply', () {
    test('full-string: the tail goes, the reply stays', () {
      expect(
        canonicalizeReasoning('hink> To impress, I stand.'),
        ' To impress, I stand.',
      );
      expect(canonicalizeReasoning('think> Hi.'), ' Hi.');
      expect(canonicalizeReasoning('\n</think>\nHi.'), '\nHi.');
      expect(canonicalizeReasoning('nk> Hi.'), ' Hi.');
    });

    test('only at the head, never mid-reply, never a bare >', () {
      expect(
        canonicalizeReasoning('The link> stays as typed.'),
        'The link> stays as typed.',
      );
      expect(canonicalizeReasoning('> quoted line'), '> quoted line');
      expect(canonicalizeReasoning('k> too short'), 'k> too short');
      expect(canonicalizeReasoning('thinking aloud'), 'thinking aloud');
    });

    test('streaming: the split tail is held, then dropped', () {
      final r = ReasoningMarkerRewriter(keep: false);
      expect(r.push('hin'), '');
      expect(r.push('k> To impress'), ' To impress');
      expect(r.push(', I stand.'), ', I stand.');
      expect(r.finish(), '');
    });

    test('streaming: ordinary prose starting with t is not lost', () {
      final r = ReasoningMarkerRewriter();
      final a = r.push('t');
      final b = r.push('hey left.');
      expect('$a$b', 'they left.');
      expect(r.finish(), '');
    });

    test('ingest with thinking off: the bubble never sees the tail', () {
      final i = ReasoningIngest(wrap: false);
      final a = i.onContent('hin');
      final b = i.onContent('k> "Stay."');
      final c = i.finish();
      expect('$a$b$c', ' "Stay."');
    });

    test('an already-stored reply with the tail displays clean', () {
      final msg = ChatMessage(
        text: 'think> "Stay."',
        sender: 'Nemu',
        isUser: false,
      );
      expect(msg.displayText, '"Stay."');
      expect(msg.toPromptHistoryLine(), isNot(contains('think>')));
    });
  });

  group('ChatMessage + strip floor', () {
    test('stored Gemma dump: Thought chip, spoken body, history-safe', () {
      final msg = ChatMessage(
        text:
            '<|channel>thought\nThe user resisted.\n<channel|>"You declined."',
        sender: 'Nemu',
        isUser: false,
      );
      expect(msg.hasThinking, isTrue);
      expect(msg.thinkingContent, contains('resisted'));
      expect(msg.displayText, '"You declined."');
      expect(msg.toPromptHistoryLine(), contains('You declined'));
      expect(msg.toPromptHistoryLine(), isNot(contains('resisted')));
    });

    test('stripThinkTags peels Gemma for TTS', () {
      expect(stripThinkTags('<|channel>thought\nnope<channel|>hello'), 'hello');
    });
  });
}
