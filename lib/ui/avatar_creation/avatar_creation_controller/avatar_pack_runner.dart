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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController;

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/expression_pack_qc.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';

import 'avatar_run_stage.dart';
import 'avatar_card_anchor.dart';
import 'avatar_qc_gate.dart';

/// The pack's variation strength — the Studio's field-tested default (0.5
/// barely moves the face; 0.7 changes it while the base holds identity). The
/// creator step deliberately has no slider: one good default, zero friction.
const double kCreatorPackDenoise = 0.7;

/// The generation steps of a creator run: the base portrait and the
/// expression pack (with its vision QC and import). Owns the pack's session,
/// QC pass and counters; the run's stage stays with the caller, moved through
/// [setStage] and [fail].
class AvatarPackRunner {
  AvatarPackRunner({
    required this.storage,
    required this.imageGen,
    required this.repository,
    required this.anchor,
    required this.qcGate,
    required this.promptController,
    required this.promptRules,
    required this.emotions,
    required this.applyPortrait,
    required this.isDisposed,
    required this.isCancelled,
    required this.onCancelled,
    required this.setStage,
    required this.fail,
    required this.notify,
  });

  final StorageService storage;
  final ImageGenService imageGen;
  final CharacterRepository repository;
  final AvatarCardAnchor anchor;
  final AvatarQcGate qcGate;
  final TextEditingController promptController;
  final ExpressionPromptRules Function() promptRules;

  /// The emotions the pack would generate now.
  final List<String> Function() emotions;
  final Future<bool> Function(Uint8List bytes) applyPortrait;
  final bool Function() isDisposed;
  final bool Function() isCancelled;

  /// The pack session was cancelled from outside the creator.
  final VoidCallback onCancelled;
  final ValueChanged<AvatarRunStage> setStage;
  final ValueChanged<String> fail;
  final VoidCallback notify;

  /// The pack's base was a JPEG or WebP that was converted to a PNG.
  bool packBaseConverted = false;
  ExpressionPackSession? session;
  ExpressionPackQc? qc;
  int importedCount = 0;
  int flaggedExcluded = 0;
  bool? activePackEditMode;

  void reset() {
    activePackEditMode = null;
    importedCount = 0;
    flaggedExcluded = 0;
    packBaseConverted = false;
  }

  /// Generate + apply the base portrait from the current prompt. Drives the
  /// portrait stage (spinner), returns true on success (portraitBytes set) or
  /// false after calling [fail]. Shared by the initial run and the review
  /// gate's regenerate so both behave identically.
  Future<bool> generatePortrait() async {
    setStage(AvatarRunStage.portrait);
    Uint8List? bytes;
    try {
      bytes = await imageGen.generateImage(
        prompt: promptController.text.trim(),
        isPortrait: true,
      );
    } catch (e) {
      debugPrint('[AvatarCreation] portrait generation failed: $e');
      bytes = null;
    }
    if (isDisposed()) return false;
    if (bytes == null) {
      fail(
        imageGen.statusMessage.isNotEmpty
            ? imageGen.statusMessage
            : 'Portrait generation returned no image.',
      );
      return false;
    }
    // Deliberately applied even when cancel arrived mid-generation: the same
    // contract as the pack session, whose in-flight slot "finishes, then stops"
    // and KEEPS the result — cancel skips future work, it never discards an
    // image the user already waited for.
    await applyPortrait(bytes);
    if (isDisposed()) return false;
    return true;
  }

  Future<void> runPack(Uint8List? base) async {
    if (base == null) {
      fail('The expression pack needs a portrait to build from.');
      return;
    }
    String? refused;
    final normalized = await preparePackBase(
      base,
      onRefused: (r) => refused = r.message,
    );
    if (isDisposed()) return;
    if (normalized == null) {
      fail(refused ?? 'The portrait image could not be decoded.');
      return;
    }
    packBaseConverted = normalized.converted;
    // The same decision as Studio's pack dialog: a ComfyUI Edit graph that is
    // not ready, or a remote API without an edit model, stops with the reason.
    final plan = await planExpressionPack(storage);
    if (isDisposed() || isCancelled()) return;
    if (!plan.canStart) {
      fail(plan.refusal!);
      return;
    }
    final editMode = plan.edit;
    activePackEditMode = editMode;
    if (editMode) {
      // Explicit stage: the swap itself is graceful (the model rides each
      // request; DT/Comfy load-unload themselves) — the cost is load TIME.
      setStage(AvatarRunStage.switching);
      await imageGen.nudgeComfyFree();
      if (isDisposed()) return;
    }
    final emotions = this.emotions();
    if (emotions.isEmpty) return;

    final flight = await beginExpressionPack(
      imageGen: imageGen,
      plan: plan,
      promptRules: promptRules(),
      emotions: emotions,
      basePrompt: '${promptController.text.trim()}, $kExpressionFraming',
      negativePrompt: storage.imageGenSettings.imageGenNegativePrompt,
      denoise: kCreatorPackDenoise,
      size: '${normalized.width}x${normalized.height}',
      baseImage: normalized.bytes,
      characterName: 'Character creator',
      onCancelled: () {
        onCancelled();
      },
    );
    if (isDisposed()) return;
    final s = flight.session;
    if (s == null) {
      fail(
        flight.busy
            ? kAlreadyGeneratingMessage
            : (flight.error ?? 'The expression pack could not start.'),
      );
      return;
    }
    _replaceSession(s);
    setStage(AvatarRunStage.pack);
    await flight.done;
    if (isDisposed()) return;

    if (qcGate.enabled && s.doneCount > 0 && !isCancelled()) {
      setStage(AvatarRunStage.qc);
      final fire = await qcGate.visionFire();
      if (isDisposed()) return;
      if (fire != null) {
        final q = ExpressionPackQc(
          slots: s.slots,
          baseImageB64: base64Encode(normalized.bytes),
          fire: fire,
        );
        _replaceQc(q);
        await q.run();
        if (isDisposed()) return;
        // Unattended flow: flagged images are held back from the gallery
        // (same semantics as the grid's "Uncheck flagged", applied for you).
        final slots = s.slots;
        for (var i = 0; i < slots.length; i++) {
          final verdict = slots[i].qc;
          if (verdict != null && !verdict.pass && slots[i].keep) {
            s.setKeep(i, false);
            flaggedExcluded++;
          }
        }
      }
    }

    // Cancel keeps completed images — import whatever finished.
    setStage(AvatarRunStage.importing);
    final card = anchor.card!;
    importedCount = await ExpressionPackImporter.importPack(
      repository: repository,
      storage: storage,
      characterDbId: card.dbId!,
      characterName: card.name,
      slots: s.slots,
    );
    anchor.addEmotions([
      for (final slot in s.slots)
        if (slot.state == ExpressionSlotState.done && slot.keep) slot.emotion,
    ]);
  }

  void _replaceSession(ExpressionPackSession s) {
    session?.removeListener(notify);
    if (session != null) expressionPackBoard.release(session!);
    session?.dispose();
    session = s;
    s.addListener(notify);
  }

  void _replaceQc(ExpressionPackQc q) {
    qc?.removeListener(notify);
    qc?.dispose();
    qc = q;
    q.addListener(notify);
  }

  void dispose() {
    session?.cancel();
    session?.removeListener(notify);
    if (session != null) expressionPackBoard.release(session!);
    session?.dispose();
    qc?.cancel();
    qc?.removeListener(notify);
    qc?.dispose();
  }
}
