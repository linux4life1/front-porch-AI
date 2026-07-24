// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/services/image_prompt/expression_prompts.dart';

void main() {
  group('ExpressionPackSession', () {
    test('editMode switches the positive prompt from img2img tags to an '
        'EDIT INSTRUCTION (customPrompt still wins in both modes, since it is '
        'checked first)', () {
      ExpressionPackSession make(bool editMode) => ExpressionPackSession(
        emotions: const ['joy'],
        basePrompt: 'a portrait of luna',
        negativePrompt: 'np',
        denoise: 0.7,
        editMode: editMode,
        generate:
            ({
              required String prompt,
              required String negativePrompt,
              required int seed,
              required double denoise,
            }) async => null,
      );
      // img2img: geometry modifier leads, base composition trails.
      final img2img = make(false).effectivePromptFor(0);
      expect(img2img, contains(kExpressionModifiers['joy']!));
      expect(img2img, contains('a portrait of luna'));
      expect(img2img, isNot(contains('Change only')));
      // edit: an instruction off the base portrait, no base-composition prompt.
      final edit = make(true).effectivePromptFor(0);
      expect(edit, expressionEditInstruction('joy'));
      expect(edit, contains('Change only the facial expression'));
      expect(edit, isNot(contains('a portrait of luna')));
    });

    test('run() drives all slots pending → done with ONE shared seed '
        'and emotion-first prompts', () async {
      final seeds = <int>[];
      final prompts = <String>[];
      final negatives = <String>[];
      Future<Uint8List?> gen({
        required String prompt,
        required String negativePrompt,
        required int seed,
        required double denoise,
      }) async {
        seeds.add(seed);
        prompts.add(prompt);
        negatives.add(negativePrompt);
        return Uint8List.fromList([seeds.length]);
      }

      final session = ExpressionPackSession(
        emotions: const ['joy', 'anger', 'neutral'],
        basePrompt: 'a portrait of luna',
        negativePrompt: 'np',
        denoise: 0.7,
        generate: gen,
      );

      expect(session.slots, hasLength(3));
      expect(session.pendingCount, 3);
      expect(session.seed, greaterThanOrEqualTo(0));

      await session.run();

      expect(session.isRunning, isFalse);
      expect(session.doneCount, 3);
      expect(session.pendingCount, 0);
      for (final slot in session.slots) {
        expect(slot.state, ExpressionSlotState.done);
        expect(slot.bytes, isNotNull);
        expect(slot.keep, isTrue);
        expect(slot.error, isNull);
      }
      expect(seeds, hasLength(3));
      // ONE shared seed for the initial run: at pack denoise the noise picks
      // the drift direction for fine identity features (eye color, face
      // shape) — per-slot seeds made each emotion drift its own way and the
      // pack stopped looking like one character. Emotion differentiation is
      // the geometry-prompt's job; fresh noise is what RE-ROLLS are for.
      expect(seeds.toSet(), hasLength(1), reason: 'pack-wide consistency');
      expect(seeds.first, session.seed);
      // Emotion leads the prompt: front tokens carry the most weight.
      expect(prompts[0], '${kExpressionModifiers['joy']}, a portrait of luna');
      expect(prompts[2], startsWith(kExpressionModifiers['neutral']!));
      // Per-emotion counter-cues ride the negative prompt (free rider: CFG-1
      // models ignore negatives; classic CFG backends get real steering).
      expect(negatives[0], 'np, ${kExpressionNegatives['joy']}');
      expect(negatives[1], 'np, ${kExpressionNegatives['anger']}');
    });

    test('explicit constructor seed is honored', () async {
      final seeds = <int>[];
      final session = ExpressionPackSession(
        emotions: const ['joy'],
        basePrompt: 'p',
        negativePrompt: 'np',
        denoise: 0.7,
        seed: 42,
        generate: ({required String prompt, required String negativePrompt, required int seed, required double denoise}) async {
          seeds.add(seed);
          return Uint8List.fromList([1]);
        },
      );
      expect(session.seed, 42);
      await session.run();
      expect(seeds, [42]);
    });

    test('null generator result → slot failed with error', () async {
      final session = ExpressionPackSession(
        emotions: const ['joy'],
        basePrompt: 'p',
        negativePrompt: 'np',
        denoise: 0.7,
        generate: ({required String prompt, required String negativePrompt, required int seed, required double denoise}) async => null,
      );
      await session.run();
      final slot = session.slots.single;
      expect(slot.state, ExpressionSlotState.failed);
      expect(slot.error, isNotNull);
      expect(session.doneCount, 0);
      expect(session.keptCount, 0);
    });

    test('throwing generator → failed, run continues to later slots', () async {
      Future<Uint8List?> gen({
        required String prompt,
        required String negativePrompt,
        required int seed,
        required double denoise,
      }) async {
        if (prompt.contains(kExpressionModifiers['anger']!)) {
          throw Exception('boom');
        }
        return Uint8List.fromList([1]);
      }

      final session = ExpressionPackSession(
        emotions: const ['joy', 'anger', 'neutral'],
        basePrompt: 'p',
        negativePrompt: 'np',
        denoise: 0.7,
        generate: gen,
      );
      await session.run();
      expect(session.slots[0].state, ExpressionSlotState.done);
      expect(session.slots[1].state, ExpressionSlotState.failed);
      expect(session.slots[1].error, contains('boom'));
      expect(session.slots[2].state, ExpressionSlotState.done);
      expect(session.doneCount, 2);
    });

    test('cancel() between slots leaves remainder pending; run() resumes', () async {
      late ExpressionPackSession session;
      var calls = 0;
      Future<Uint8List?> gen({
        required String prompt,
        required String negativePrompt,
        required int seed,
        required double denoise,
      }) async {
        calls++;
        if (calls == 2) session.cancel();
        return Uint8List.fromList([calls]);
      }

      session = ExpressionPackSession(
        emotions: const ['joy', 'anger', 'fear', 'sadness'],
        basePrompt: 'p',
        negativePrompt: 'np',
        denoise: 0.7,
        generate: gen,
      );
      await session.run();
      // The in-flight (2nd) slot finishes; the rest stay pending.
      expect(session.isRunning, isFalse);
      expect(session.doneCount, 2);
      expect(session.pendingCount, 2);
      expect(session.slots[2].state, ExpressionSlotState.pending);
      expect(session.slots[3].state, ExpressionSlotState.pending);

      await session.run(); // resume path
      expect(session.doneCount, 4);
      expect(session.pendingCount, 0);
      expect(calls, 4);
    });

    test('reroll() uses a fresh seed and only touches that slot', () async {
      final seeds = <int>[];
      var counter = 0;
      Future<Uint8List?> gen({
        required String prompt,
        required String negativePrompt,
        required int seed,
        required double denoise,
      }) async {
        seeds.add(seed);
        counter++;
        return Uint8List.fromList([counter]);
      }

      final session = ExpressionPackSession(
        emotions: const ['joy', 'anger'],
        basePrompt: 'p',
        negativePrompt: 'np',
        denoise: 0.7,
        generate: gen,
      );
      await session.run();
      final joyBytes = session.slots[0].bytes;
      final angerBytes = session.slots[1].bytes;

      await session.reroll(1);
      expect(seeds, hasLength(3));
      expect(seeds[2], session.seed,
          reason: 'default re-roll keeps the pack seed (levers change it)');
      expect(session.seed, seeds[0], reason: 'session seed must not change');
      expect(session.slots[0].bytes, same(joyBytes));
      expect(session.slots[1].bytes, isNot(same(angerBytes)));
      expect(session.slots[1].state, ExpressionSlotState.done);
    });

    test(
      'reroll() marks the session running for its duration — generations '
      'serialize (single-GPU backends) and the UI can disable other buttons',
      () async {
        final gate = Completer<void>();
        var calls = 0;
        final session = ExpressionPackSession(
          emotions: const ['joy', 'anger'],
          basePrompt: 'p',
          negativePrompt: 'np',
          denoise: 0.7,
          generate: ({required String prompt, required String negativePrompt, required int seed, required double denoise}) async {
            calls++;
            // Only the reroll (3rd call) blocks; the initial run flows through.
            if (calls > 2) await gate.future;
            return Uint8List.fromList([calls]);
          },
        );
        await session.run();
        expect(session.doneCount, 2);

        final rerolling = session.reroll(0); // blocks on the gate
        expect(session.isRunning, isTrue);
        await session.reroll(1); // must no-op while the reroll is in flight
        expect(calls, 3, reason: 'no concurrent second generation');
        gate.complete();
        await rerolling;
        expect(session.isRunning, isFalse);
      },
    );

    test(
      're-roll keeps the slot seed by default; prompt/strength overrides '
      'stick; an explicit newSeed draws fresh noise and stays sticky',
      () async {
        final calls = <({String prompt, int seed, double denoise})>[];
        final session = ExpressionPackSession(
          emotions: const ['joy'],
          basePrompt: 'base',
          negativePrompt: 'np',
          denoise: 0.7,
          generate:
              ({
                required String prompt,
                required String negativePrompt,
                required int seed,
                required double denoise,
              }) async {
                calls.add((prompt: prompt, seed: seed, denoise: denoise));
                return Uint8List.fromList([calls.length]);
              },
        );
        await session.run();
        final auto = '${kExpressionModifiers['joy']}, base';
        expect(calls.last.seed, session.seed);
        expect(calls.last.denoise, 0.7);
        expect(session.effectivePromptFor(0), auto);
        expect(session.effectiveDenoiseFor(0), 0.7);

        // Default re-roll: SAME seed (pack consistency) — the editor's
        // prompt/strength levers are what change the result.
        await session.reroll(
          0,
          promptOverride: '  gentle smile, base  ',
          denoiseOverride: 0.55,
        );
        expect(calls.last.seed, session.seed);
        expect(calls.last.prompt, 'gentle smile, base');
        expect(calls.last.denoise, 0.55);
        expect(session.effectivePromptFor(0), 'gentle smile, base');
        expect(session.effectiveDenoiseFor(0), 0.55);

        // Explicit new noise: fresh seed, sticky for later re-rolls.
        await session.reroll(0, newSeed: true);
        final rolled = calls.last.seed;
        expect(rolled, isNot(session.seed));
        expect(calls.last.prompt, 'gentle smile, base'); // custom sticks
        expect(calls.last.denoise, 0.55); // strength sticks
        await session.reroll(0);
        expect(calls.last.seed, rolled, reason: 'rolled seed is sticky');

        // Blank override is ignored (no accidental prompt wipe).
        await session.reroll(0, promptOverride: '   ');
        expect(session.slots[0].customPrompt, 'gentle smile, base');
      },
    );

    test('reroll() retries failed slots', () async {
      var failNext = true;
      final session = ExpressionPackSession(
        emotions: const ['joy'],
        basePrompt: 'p',
        negativePrompt: 'np',
        denoise: 0.7,
        generate: ({required String prompt, required String negativePrompt, required int seed, required double denoise}) async {
          if (failNext) {
            failNext = false;
            return null;
          }
          return Uint8List.fromList([7]);
        },
      );
      await session.run();
      expect(session.slots[0].state, ExpressionSlotState.failed);
      await session.reroll(0);
      expect(session.slots[0].state, ExpressionSlotState.done);
      expect(session.slots[0].error, isNull);
      expect(session.doneCount, 1);
    });

    test('reroll() and run() are no-ops while running; bad index is safe', () async {
      final gate = Completer<void>();
      var calls = 0;
      final session = ExpressionPackSession(
        emotions: const ['joy', 'anger'],
        basePrompt: 'p',
        negativePrompt: 'np',
        denoise: 0.7,
        generate: ({required String prompt, required String negativePrompt, required int seed, required double denoise}) async {
          calls++;
          await gate.future;
          return Uint8List.fromList([calls]);
        },
      );
      final running = session.run();
      expect(session.isRunning, isTrue);
      expect(calls, 1);

      await session.run(); // reentrancy guard: no-op
      expect(calls, 1);

      await session.reroll(1); // no-op while running
      expect(calls, 1);
      expect(session.slots[1].state, ExpressionSlotState.pending);

      gate.complete();
      await running;
      expect(session.doneCount, 2);
      expect(calls, 2);

      await session.reroll(99); // out of range: no-op, no throw
      await session.reroll(-1);
      expect(calls, 2);
    });

    test('setKeep flips keep and keptCount/doneCount track it', () async {
      final session = ExpressionPackSession(
        emotions: const ['joy', 'anger'],
        basePrompt: 'p',
        negativePrompt: 'np',
        denoise: 0.7,
        generate: ({required String prompt, required String negativePrompt, required int seed, required double denoise}) async =>
            Uint8List.fromList([1]),
      );
      await session.run();
      expect(session.doneCount, 2);
      expect(session.keptCount, 2);
      session.setKeep(0, false);
      expect(session.slots[0].keep, isFalse);
      expect(session.keptCount, 1);
      expect(session.doneCount, 2);
      session.setKeep(0, true);
      expect(session.keptCount, 2);
      session.setKeep(99, true); // out of range: safe no-op
    });

    test('dispose mid-generation is safe (no post-dispose mutation)', () async {
      final gate = Completer<void>();
      final session = ExpressionPackSession(
        emotions: const ['joy'],
        basePrompt: 'p',
        negativePrompt: 'np',
        denoise: 0.7,
        generate: ({required String prompt, required String negativePrompt, required int seed, required double denoise}) async {
          await gate.future;
          return Uint8List.fromList([1]);
        },
      );
      final running = session.run();
      session.dispose();
      gate.complete();
      // Must complete without throwing — notifying a disposed ChangeNotifier
      // would assert in debug mode, so this proves the disposed bail-out.
      await running;
    });
  });
}
