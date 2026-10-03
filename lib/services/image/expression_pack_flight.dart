// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';

/// A pack start. [session] is null when the pack did not start: [busy] when
/// another generation holds the lock, otherwise [error] says why. [done]
/// finishes with the names of the pictures made.
class ExpressionPackFlight {
  const ExpressionPackFlight({
    required this.session,
    required this.done,
    required this.busy,
    this.error,
  });

  final ExpressionPackSession? session;
  final Future<List<String>> done;
  final bool busy;
  final String? error;
}

/// Starts a pack under one hold of the generation lock and shows it on
/// [board]. Every picture goes through the same frame call; nothing here
/// decides between Edit and Create: [plan] already did, and a plan that
/// cannot start is a mistake of the caller.
///
/// Cancelling the session (from any screen) also stops the picture being made.
/// [onCancelled] tells the screen that started the pack.
Future<ExpressionPackFlight> beginExpressionPack({
  required ImageGenService imageGen,
  required PackPlan plan,
  required List<String> emotions,
  required String basePrompt,
  required String negativePrompt,
  required double denoise,
  required String size,
  required Uint8List baseImage,
  required String characterName,
  String? characterId,
  ExpressionPromptRules? promptRules,
  PackOrigin origin = PackOrigin.desktop,
  bool replaceExisting = true,
  String? note,
  ExpressionPackBoard? board,
  void Function()? onCancelled,
}) async {
  assert(plan.canStart, 'a pack that cannot start was started');
  final onBoard = board ?? expressionPackBoard;
  final edit = plan.edit;
  final rules = (promptRules ?? ExpressionPromptRules()).copy();
  final ready = Completer<ExpressionPackSession?>();
  String? error;
  final started = imageGen.startExpressionPack(emotions, (names) async {
    try {
      final session = ExpressionPackSession(
        emotions: names,
        basePrompt: basePrompt,
        negativePrompt: negativePrompt,
        denoise: denoise,
        editMode: edit,
        promptRules: rules,
        onCancel: () {
          unawaited(imageGen.cancelJob());
          onCancelled?.call();
        },
        generate:
            ({
              required String prompt,
              required String negativePrompt,
              required int seed,
              required double denoise,
            }) async {
              final bytes = await imageGen.expressionFrame(
                prompt: prompt,
                negativePrompt: negativePrompt,
                size: size,
                referenceImage: baseImage,
                seed: seed,
                denoise: denoise,
                intent: edit ? StudioIntent.edit : StudioIntent.create,
                editStrength: edit ? denoise : null,
              );
              if (bytes == null) {
                final why = imageGen.statusMessage.trim();
                if (why.isNotEmpty) throw Exception(why);
              }
              return bytes;
            },
      );
      onBoard.publish(
        PackRun(
          session: session,
          mode: edit ? PackMode.edit : PackMode.img2img,
          origin: origin,
          characterId: characterId,
          characterName: characterName,
          replaceExisting: replaceExisting,
          note: note,
        ),
      );
      ready.complete(session);
      await session.run();
      return [
        for (final slot in session.slots)
          if (slot.state == ExpressionSlotState.done) slot.emotion,
      ];
    } catch (e) {
      debugPrint('expression pack did not run: $e');
      error = 'The expression pack could not start.';
      if (!ready.isCompleted) ready.complete(null);
      return const <String>[];
    }
  });
  // A refused start never calls the driver.
  final finished = started.then((names) {
    if (!ready.isCompleted) ready.complete(null);
    return names ?? const <String>[];
  });
  unawaited(finished.then<void>((_) {}, onError: (Object _) {}));
  final session = await ready.future;
  return ExpressionPackFlight(
    session: session,
    done: finished,
    busy: session == null && error == null,
    error: session == null ? error : null,
  );
}
