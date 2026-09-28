// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/services/image/expression_pack_route.dart';
import 'package:front_porch_ai/services/image/image_job.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

/// A pack start. [session] is null when another generation already holds the
/// lock. [done] finishes with the saved filenames, never image bytes.
class ExpressionPackFlight {
  const ExpressionPackFlight({
    required this.session,
    required this.done,
    required this.busy,
  });

  final ExpressionPackSession? session;
  final Future<List<String>?> done;

  /// True when another generation already holds the lock.
  final bool busy;
}

/// Holds the single-flight lock and runs every emotion through that one
/// driver. The driver does not call [ImageGenService.generateImage].
Future<ExpressionPackFlight> beginExpressionPack({
  required ImageGenService imageGen,
  required ImageGenSettings settings,
  required List<String> emotions,
  required String basePrompt,
  required String negativePrompt,
  required double denoise,
  required String size,
  required Uint8List baseImage,
  required String accountId,
  void Function()? onExternalCancel,
}) {
  final ready = Completer<ExpressionPackSession?>();
  final done = imageGen.startExpressionPack(emotions, (names) async {
    try {
      final editMode = await ImageReferenceResolver.packEditModeForGeneration(
        settings,
      );
      final session = ExpressionPackSession(
        emotions: names,
        basePrompt: basePrompt,
        negativePrompt: negativePrompt,
        denoise: denoise,
        editMode: editMode,
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
                intent: editMode ? StudioIntent.edit : StudioIntent.create,
                editStrength: editMode ? denoise : null,
              );
              if (bytes == null) {
                final why = imageGen.statusMessage.trim();
                if (why.isNotEmpty) {
                  throw Exception(why);
                }
              }
              return bytes;
            },
      );
      if (!ready.isCompleted) ready.complete(session);
      void publish() {
        expressionPackBoard.publish(
          accountId: accountId,
          running: session.isRunning,
          slots: session.slots,
          onCancel: () {
            session.cancel();
            onExternalCancel?.call();
          },
        );
      }

      session.addListener(publish);
      publish();
      await session.run();
      publish();
      return [
        for (final slot in session.slots)
          if (slot.state == ExpressionSlotState.done) '${slot.emotion}.png',
      ];
    } catch (e) {
      debugPrint('expression pack did not start: ${e.runtimeType}');
      if (!ready.isCompleted) {
        ready.complete(null);
      }
      return const <String>[];
    }
  });
  unawaited(done.then<void>((_) {}, onError: (Object _) {}));
  final busy =
      !ready.isCompleted && imageGen.statusMessage == kAlreadyGeneratingMessage;
  if (busy) {
    ready.complete(null);
  }
  return ready.future.then(
    (session) => ExpressionPackFlight(
      session: session,
      done: done,
      busy: busy && session == null,
    ),
  );
}
