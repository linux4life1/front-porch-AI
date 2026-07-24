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

part of 'avatar_creation_controller.dart';

/// Run-step internals for [AvatarCreationController], split out to keep both
/// files under the 500-LOC cap (same `part of` + private-extension pattern as
/// settings_page). Direct access to the controller's private state, so
/// behavior is identical to living inline.
extension _AvatarCreationRunSteps on AvatarCreationController {
  /// Generate + apply the base portrait from the current prompt. Drives the
  /// portrait stage (spinner), returns true on success (portraitBytes set) or
  /// false after calling [_fail]. Shared by the initial run and the review
  /// gate's regenerate so both behave identically.
  Future<bool> _generatePortrait() async {
    _setStage(AvatarRunStage.portrait);
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
    if (_disposed) return false;
    if (bytes == null) {
      _fail(
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
    if (_disposed) return false;
    return true;
  }

  /// Run the expression pack (when enabled) off [base], then land on done.
  /// Shared by the uploaded-base run and the review gate's continue.
  Future<void> _generatePackAndFinish(Uint8List? base) async {
    if (packEnabled && packPossible && !_cancelRequested) {
      await _runPack(base);
      if (_disposed || stage == AvatarRunStage.failed) return;
    }
    _setStage(AvatarRunStage.done);
  }

  Future<void> _runPack(Uint8List? base) async {
    if (base == null) {
      _fail('The expression pack needs a portrait to build from.');
      return;
    }
    final normalized = normalizePackBase(base);
    if (normalized == null) {
      _fail('The portrait image could not be decoded.');
      return;
    }
    final editMode = packEditModeNow;
    if (editMode) {
      // Explicit stage: the swap itself is graceful (the model rides each
      // request; DT/Comfy load-unload themselves) — the cost is load TIME.
      _setStage(AvatarRunStage.switching);
      await imageGen.nudgeComfyFree();
      if (_disposed) return;
    }
    final emotions = missingEmotions;
    if (emotions.isEmpty) return;

    final s = ExpressionPackSession(
      emotions: emotions,
      basePrompt: '${promptController.text.trim()}, $kExpressionFraming',
      negativePrompt: storage.imageGenSettings.imageGenNegativePrompt,
      denoise: kCreatorPackDenoise,
      editMode: editMode,
      generate:
          ({
            required String prompt,
            required String negativePrompt,
            required int seed,
            required double denoise,
          }) => imageGen.generateImage(
            prompt: prompt,
            negativePrompt: negativePrompt,
            size: '${normalized.width}x${normalized.height}',
            referenceImage: normalized.bytes,
            seed: seed,
            denoise: denoise,
            intent: editMode ? StudioIntent.edit : StudioIntent.create,
            editStrength: editMode ? denoise : null,
          ),
    );
    _replaceSession(s);
    _setStage(AvatarRunStage.pack);
    await s.run();
    if (_disposed) return;

    if (qcEnabled && s.doneCount > 0 && !_cancelRequested) {
      _setStage(AvatarRunStage.qc);
      _visionFire ??= await resolveVisionFire();
      if (_disposed) return;
      final fire = _visionFire;
      if (fire != null) {
        final q = ExpressionPackQc(
          slots: s.slots,
          baseImageB64: base64Encode(normalized.bytes),
          fire: fire,
        );
        _replaceQc(q);
        await q.run();
        if (_disposed) return;
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
    _setStage(AvatarRunStage.importing);
    importedCount = await ExpressionPackImporter.importPack(
      repository: repository,
      storage: storage,
      characterDbId: _card!.dbId!,
      characterName: _card!.name,
      slots: s.slots,
    );
    _existingEmotions = {
      ..._existingEmotions,
      for (final slot in s.slots)
        if (slot.state == ExpressionSlotState.done && slot.keep) slot.emotion,
    };
  }

  /// Single-flight: two quick user actions before the first persist lands
  /// (upload + ZIP, say) must NOT both see a null dbId and addCharacter
  /// twice — every concurrent caller awaits the ONE in-flight save.
  Future<bool> _ensureCard() {
    if (_card?.dbId != null && _ensuring == null) {
      return _loadExistingEmotions().then((_) => true);
    }
    return _ensuring ??= _ensureCardOnce().whenComplete(() => _ensuring = null);
  }

  Future<bool> _ensureCardOnce() async {
    if (_card?.dbId != null) return true;
    final c = await ensureCardSaved();
    if (_disposed) return false;
    if (c == null || c.dbId == null) return false;
    _card = c;
    await _loadExistingEmotions();
    if (!_disposed) _notify();
    return true;
  }

  Future<void> _loadExistingEmotions() async {
    final id = _card?.dbId;
    if (id == null) return;
    _existingEmotions = (await repository.getAvatarImages(id))
        .map((a) => (a.label ?? '').toLowerCase())
        .where((l) => l.isNotEmpty && l != AvatarImage.lookLabel)
        .toSet();
  }

  void _setStage(AvatarRunStage s) {
    stage = s;
    if (!_disposed) _notify();
  }

  void _fail(String message) {
    statusDetail = message;
    _setStage(AvatarRunStage.failed);
  }

  void _replaceSession(ExpressionPackSession s) {
    session?.removeListener(_notify);
    session?.dispose();
    session = s;
    s.addListener(_notify);
  }

  void _replaceQc(ExpressionPackQc q) {
    qc?.removeListener(_notify);
    qc?.dispose();
    qc = q;
    q.addListener(_notify);
  }
}
