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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show TextEditingController;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/expression_pack_qc.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/services/portrait_promotion.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_io.dart';

import 'avatar_creation_controller/avatar_creation_controller.dart';

export 'avatar_creation_controller/avatar_pack_runner.dart'
    show kCreatorPackDenoise;
export 'avatar_creation_controller/avatar_run_stage.dart';

/// State + orchestration for the shared AvatarGenerationPanel (phase #12).
///
/// Locked contract (see project_avatar_gallery.md, decisions a–o):
/// - The card is created and saved BEFORE any generation ([ensureCardSaved]
///   — a failure or cancel can never cost the character's writing).
/// - Portrait = txt2img on the CREATE model slot; expression pack = the
///   existing [ExpressionPackSession] with the exact edit-vs-img2img decision
///   the Studio's pack dialog uses ([ImageReferenceResolver.packEditMode],
///   over the EDIT slot), base image = generated OR uploaded portrait.
/// - Upload count follows the pack toggle: pack ON → exactly ONE upload (it
///   IS the pack's identity base); pack OFF → multi-upload with emotion
///   tagging (null emotion = a gallery look).
/// - Cancel keeps completed images; everything lands via the existing
///   addLook/addAvatar/imagePath plumbing.
///
/// Pure ChangeNotifier — every dependency is injected, so the run
/// orchestration and the gating rules are unit-testable without widgets.
class AvatarCreationController extends ChangeNotifier {
  AvatarCreationController({
    required this.ensureCardSaved,
    required this.repository,
    required this.storage,
    required this.imageGen,
    required this.resolveVisionFire,
    required this.peekVisionSupport,
    required String initialPrompt,
    CharacterCard? card,
    this.existingPortraitPath,
  }) : promptController = TextEditingController(text: initialPrompt),
       _packPromptRules = storage.expressionSettings.expressionPromptRules
           .copy() {
    _anchor = AvatarCardAnchor(
      ensureCardSaved: ensureCardSaved,
      repository: repository,
      isDisposed: () => _disposed,
      notify: notifyListeners,
      card: card,
    );
    _engine = AvatarEngineProbe(
      storage: storage,
      imageGen: imageGen,
      isDisposed: () => _disposed,
      notify: notifyListeners,
    );
    _qcGate = AvatarQcGate(
      resolveVisionFire: resolveVisionFire,
      peekVisionSupport: peekVisionSupport,
      isDisposed: () => _disposed,
      notify: notifyListeners,
    );
    _runner = AvatarPackRunner(
      storage: storage,
      imageGen: imageGen,
      repository: repository,
      anchor: _anchor,
      qcGate: _qcGate,
      promptController: promptController,
      promptRules: () => _packPromptRules,
      emotions: () => missingEmotions,
      applyPortrait: applyPortrait,
      isDisposed: () => _disposed,
      isCancelled: () => _cancelRequested,
      onCancelled: () => _cancelRequested = true,
      setStage: _setStage,
      fail: _fail,
      notify: notifyListeners,
    );
    final configured = imageGen.isConfigured;
    source = configured && existingPortraitPath == null
        ? PortraitSource.generate
        : PortraitSource.upload;
    packEnabled = configured && packPossible;
  }

  /// Host guarantee: returns a PERSISTED card (dbId set) or null on failure.
  /// The manual creator saved on step entry and returns it directly; the AI
  /// creator saves on first use (its Save & Finish then updates in place).
  final Future<CharacterCard?> Function() ensureCardSaved;

  /// A picture the card already starts with (a persona's): shown as the
  /// uploaded portrait instead of defaulting to Generate.
  final String? existingPortraitPath;

  final CharacterRepository repository;
  final StorageService storage;
  final ImageGenService imageGen;

  /// Click-time vision resolve with the Studio's warm explainer (never called
  /// automatically — probes cost a request and mis-verdict while models load).
  final Future<VisionEvalFn?> Function() resolveVisionFire;

  /// Zero-network-cost verdict for the QC gate (null = nothing known yet).
  final Future<VisionSupport?> Function() peekVisionSupport;

  /// Portrait prompt, seeded from the host's appearance/description fields —
  /// also the pack's base prompt (each emotion prepends its modifier).
  final TextEditingController promptController;

  late final AvatarCardAnchor _anchor;
  late final AvatarEngineProbe _engine;
  late final AvatarQcGate _qcGate;
  late final AvatarPackRunner _runner;

  CharacterCard? get card => _anchor.card;

  // ── Choices ───────────────────────────────────────────────────────────────
  PortraitSource source = PortraitSource.upload;
  bool packEnabled = false;
  bool fullSet = false;
  ExpressionPromptRules _packPromptRules;

  // ── Applied images ────────────────────────────────────────────────────────
  /// The portrait as applied to the card this session (uploaded or generated);
  /// also the pack's identity base.
  Uint8List? portraitBytes;

  /// Extra uploads applied this session (pack OFF only); null emotion = look.
  final List<({Uint8List bytes, String? emotion})> extraUploads = [];

  // ── Engine catalog (shared Studio config, never a second one) ────────────
  List<({String value, String label})> get modelOptions => _engine.modelOptions;
  bool? get connectionOk => _engine.connectionOk;
  bool get testingConnection => _engine.testingConnection;
  bool get loadingModels => _engine.loadingModels;

  // ── Vision QC gate ────────────────────────────────────────────────────────
  bool get qcVisible => _qcGate.visible;
  bool get qcKnownSupported => _qcGate.knownSupported;
  bool get qcEnabled => _qcGate.enabled;
  bool get resolvingVision => _qcGate.resolving;

  // ── Run state ─────────────────────────────────────────────────────────────
  AvatarRunStage stage = AvatarRunStage.idle;
  String statusDetail = '';

  /// The pack's base was a JPEG or WebP that was converted to a PNG.
  bool get packBaseConverted => _runner.packBaseConverted;
  ExpressionPackSession? get session => _runner.session;
  ExpressionPackQc? get qc => _runner.qc;
  int get importedCount => _runner.importedCount;
  int get flaggedExcluded => _runner.flaggedExcluded;
  bool _cancelRequested = false;
  bool _disposed = false;

  bool get running =>
      stage != AvatarRunStage.idle &&
      stage != AvatarRunStage.done &&
      stage != AvatarRunStage.failed;

  // ── Derived gates ─────────────────────────────────────────────────────────
  ImageGenBackend get backend =>
      ImageGenBackend.fromKey(storage.imageGenSettings.imageGenBackend);
  bool get engineReady => imageGen.isConfigured;

  /// The exact decision the Studio's pack dialog uses (edit slot + ComfyUI
  /// readiness). img2img is the automatic fallback where edit truly isn't.
  bool get packEditModeNow =>
      (running ? _runner.activePackEditMode : null) ??
      ImageReferenceResolver.packEditMode(storage.imageGenSettings);

  /// The Edit-tab view for the edit-model row (readiness copy per backend).
  ImageReferenceCapability get editCapability =>
      ImageReferenceResolver.resolveForBackend(
        backend: backend,
        modelName: storage.imageGenSettings.imageGenEditModel,
      );

  /// Pack GENERATION is possible: an engine, a portrait source to build from,
  /// and — remote only — an edit model (remote has no img2img floor).
  bool get packPossible {
    final controls = imageSurfaceFor(
      backend: backend,
      modelName: storage.imageGenSettings.imageGenEditModel,
    );
    return engineReady &&
        source != PortraitSource.none &&
        (controls.showImg2img || packEditModeNow);
  }

  List<String> get chosenSet =>
      fullSet ? kFullExpressionSet : kCuratedExpressionSet;

  /// Emotions the run would actually generate (existing labels are kept, same
  /// default as the Studio's second-run behavior).
  List<String> get missingEmotions => [
    for (final e in chosenSet)
      if (!_anchor.existingEmotions.contains(e)) e,
  ];

  /// CTA copy, or null when there is nothing to generate (upload/none-only
  /// states apply immediately and need no button).
  String? get ctaLabel {
    final wantPortrait = source == PortraitSource.generate;
    final wantPack = packEnabled && packPossible;
    final n = missingEmotions.length;
    if (wantPortrait && wantPack) {
      return 'Generate 1 portrait · $n expression${n == 1 ? '' : 's'}';
    }
    if (wantPortrait) return 'Generate 1 portrait';
    if (wantPack) return 'Generate $n expression${n == 1 ? '' : 's'}';
    return null;
  }

  bool get canRun {
    if (running || ctaLabel == null) return false;
    if (source == PortraitSource.generate) {
      return engineReady && promptController.text.trim().isNotEmpty;
    }
    // Pack-only run off an uploaded portrait.
    return portraitBytes != null;
  }

  /// Inputs lock while running, but the prompt stays editable at the review
  /// gate so the user can tweak it before regenerating the portrait.
  bool get promptEditable => !running || stage == AvatarRunStage.portraitReview;

  /// The review gate can regenerate only with a non-empty prompt.
  bool get canRegeneratePortrait =>
      stage == AvatarRunStage.portraitReview &&
      source == PortraitSource.generate &&
      promptController.text.trim().isNotEmpty;

  // ── Choice setters ────────────────────────────────────────────────────────
  void setSource(PortraitSource v) {
    if (running || source == v) return;
    source = v;
    if (!packPossible) packEnabled = false;
    notifyListeners();
  }

  void setFullSet(bool v) {
    if (fullSet == v) return;
    fullSet = v;
    notifyListeners();
  }

  void setPackEnabled(bool v) {
    if (running) return;
    packEnabled = v && packPossible;
    notifyListeners();
  }

  /// Vision QC toggle per the capability-gating design: known-supported flips
  /// directly; unknown resolves ON CLICK (warm explainer + revert on failure).
  Future<void> setQcEnabled(bool v) => _qcGate.setEnabled(v);

  ExpressionPromptRules get packPromptRules => _packPromptRules;

  void setPackPromptRules(ExpressionPromptRules rules) {
    if (running) {
      throw StateError('Stop the pack before changing its prompt rules.');
    }
    _packPromptRules = rules.copy();
    notifyListeners();
  }

  // ── Init (fire-and-forget from the panel's initState) ────────────────────
  /// One-call init: engine probe + QC gate + (when the host handed over an
  /// already-saved card) the existing-emotion labels for the CTA count.
  Future<void> init() async {
    unawaited(initQcGate());
    unawaited(refreshEngine());
    await loadExistingPortrait();
    if (_anchor.card?.dbId != null) {
      await _anchor.loadExistingEmotions();
      if (!_disposed) notifyListeners();
    }
  }

  /// Fills the portrait slot from [existingPortraitPath]. Nothing is written:
  /// the card already carries that picture.
  Future<void> loadExistingPortrait() async {
    final path = existingPortraitPath;
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (!await file.exists()) return;
      portraitBytes = await file.readAsBytes();
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('[AvatarCreation] Starting portrait unreadable: $e');
    }
  }

  /// Hidden/shown per the shipped VisionSupportResolver, WITHOUT probing:
  /// known-unsupported → the toggle doesn't exist; known-supported → shown
  /// (default off); unknown → shown, resolved on toggle.
  Future<void> initQcGate() => _qcGate.init();

  /// Connection test (local backends) + model catalog for the engine strip
  /// and the edit-model row. Mirrors the Studio settings tab's auto-test.
  Future<void> refreshEngine() => _engine.refresh();

  // ── Upload paths (apply immediately via the existing plumbing) ───────────
  /// Sets [bytes] as the card's portrait: written over the existing in-app
  /// portrait file IN PLACE (folders key members by its basename) or a fresh
  /// file when none exists, then re-embedded via updateCharacter.
  Future<bool> applyPortrait(Uint8List bytes) async {
    if (!await _anchor.ensure()) return false;
    final card = _anchor.card!;
    final target = portraitWriteTarget(card: card, storage: storage);
    await target.writeAsBytes(bytes);
    await FileImage(target).evict();
    await repository.updateCharacter(card);
    portraitBytes = bytes;
    if (!_disposed) notifyListeners();
    return true;
  }

  /// Pack-OFF extra upload: a gallery look (null emotion) or a tagged
  /// expression image. Applied immediately.
  Future<bool> addExtraUpload(Uint8List bytes, String? emotion) async {
    if (!await _anchor.ensure()) return false;
    final card = _anchor.card!;
    if (emotion == null) {
      await repository.addLook(card.dbId!, card.name, bytes);
    } else {
      await repository.addAvatar(card.dbId!, card.name, bytes, emotion);
      _anchor.addEmotions([emotion]);
    }
    extraUploads.add((bytes: bytes, emotion: emotion));
    if (!_disposed) notifyListeners();
    return true;
  }

  /// Emotion-named ZIP sprite pack (the generation alternative). Returns
  /// (added, unrecognized).
  Future<(int, int)> importExpressionZip(Uint8List zipBytes) async {
    if (!await _anchor.ensure()) return (0, 0);
    final card = _anchor.card!;
    final result = decodeSpritePack(zipBytes);
    var added = 0;
    for (final e in result.entries) {
      await repository.addAvatar(card.dbId!, card.name, e.bytes, e.emotion);
      extraUploads.add((bytes: e.bytes, emotion: e.emotion));
      _anchor.addEmotions([e.emotion]);
      added++;
    }
    if (added > 0 && !storage.expressionSettings.expressionEnabled) {
      await storage.expressionSettings.setExpressionEnabled(true);
    }
    if (!_disposed) notifyListeners();
    return (added, result.unrecognized);
  }

  // ── The run (portrait → veto gate → pack) ─────────────────────────────────
  Future<void> run() async {
    if (running || ctaLabel == null) return;
    _runner.reset();
    _cancelRequested = false;
    statusDetail = '';
    final wantPortrait = source == PortraitSource.generate;

    _setStage(AvatarRunStage.saving);
    if (!await _anchor.ensure()) {
      _fail('The character could not be saved.');
      return;
    }
    if (_cancelRequested) {
      // Cancelled during the save — nothing has generated yet, so settle
      // without spending a portrait (preserves the pre-gate short-circuit).
      _setStage(AvatarRunStage.done);
      return;
    }

    if (wantPortrait) {
      // _fail already set on error.
      if (!await _runner.generatePortrait()) return;
      if (_disposed) return;
      // Veto gate: with a pack pending, PAUSE on the generated portrait so the
      // user can regenerate it (after tweaking the prompt) before we spend time
      // on the expression pass. A cancel mid-portrait, or no pack, skips on.
      if (packEnabled && packPossible && !_cancelRequested) {
        _setStage(AvatarRunStage.portraitReview);
        return;
      }
      _setStage(AvatarRunStage.done);
      return;
    }

    // Uploaded/none base — the user already chose it; nothing to review.
    await _generatePackAndFinish(portraitBytes);
  }

  /// Review gate: regenerate the base portrait with the (possibly edited)
  /// prompt and stay paused, so the user can keep vetoing before committing to
  /// the expression pass. No-op outside the gate or with an empty prompt.
  Future<void> regeneratePortrait() async {
    if (!canRegeneratePortrait) return;
    _cancelRequested = false;
    if (!await _runner.generatePortrait()) return; // _fail set on error
    if (_disposed) return;
    _setStage(AvatarRunStage.portraitReview);
  }

  /// Review gate: accept the shown portrait. [withPack] true → run the
  /// expression pass then finish; false → finish with just the portrait.
  Future<void> continueFromReview({bool withPack = true}) async {
    if (stage != AvatarRunStage.portraitReview) return;
    _cancelRequested = false;
    if (!withPack) {
      _setStage(AvatarRunStage.done);
      return;
    }
    await _generatePackAndFinish(portraitBytes);
  }

  /// Stop after whatever is in flight; completed images always stay.
  void cancel() {
    // A listener that cancels on every notify would otherwise call this
    // again from its own notify, without end.
    if (_cancelRequested) return;
    _cancelRequested = true;
    session?.cancel();
    qc?.cancel();
    notifyListeners();
  }

  /// Run the expression pack (when enabled) off [base], then land on done.
  /// Shared by the uploaded-base run and the review gate's continue.
  Future<void> _generatePackAndFinish(Uint8List? base) async {
    if (packEnabled && packPossible && !_cancelRequested) {
      await _runner.runPack(base);
      if (_disposed || stage == AvatarRunStage.failed) return;
    }
    _setStage(AvatarRunStage.done);
  }

  void _setStage(AvatarRunStage s) {
    stage = s;
    if (!_disposed) notifyListeners();
  }

  void _fail(String message) {
    statusDetail = message;
    _setStage(AvatarRunStage.failed);
  }

  @override
  void dispose() {
    _disposed = true;
    _runner.dispose();
    promptController.dispose();
    super.dispose();
  }
}
