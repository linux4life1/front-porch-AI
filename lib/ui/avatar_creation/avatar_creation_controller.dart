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
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show TextEditingController;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/image_reference_resolver.dart';
import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/capability/model_capabilities.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/expression_pack_qc.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/image_prompt/expression_prompts.dart';
import 'package:front_porch_ai/services/portrait_promotion.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_io.dart';
import 'package:front_porch_ai/ui/image_studio/backend_catalog.dart';

part 'avatar_creation_run.dart';

/// Where the card's portrait comes from in the "Portrait & Avatars" step.
enum PortraitSource { upload, generate, none }

/// Stage of the creator generation run (drives the progress list).
///
/// [portraitReview] is the veto gate: after the base portrait generates and a
/// pack is pending, the run PAUSES here so the user can regenerate (after
/// tweaking the prompt) or accept it before the expensive expression pass.
enum AvatarRunStage {
  idle,
  saving,
  portrait,
  portraitReview,
  switching,
  pack,
  qc,
  importing,
  done,
  failed,
}

/// The pack's variation strength — the Studio's field-tested default (0.5
/// barely moves the face; 0.7 changes it while the base holds identity). The
/// creator step deliberately has no slider: one good default, zero friction.
const double kCreatorPackDenoise = 0.7;

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
  }) : promptController = TextEditingController(text: initialPrompt),
       _card = card {
    final configured = imageGen.isConfigured;
    source = configured ? PortraitSource.generate : PortraitSource.upload;
    packEnabled = configured && packPossible;
  }

  /// Host guarantee: returns a PERSISTED card (dbId set) or null on failure.
  /// The manual creator saved on step entry and returns it directly; the AI
  /// creator saves on first use (its Save & Finish then updates in place).
  final Future<CharacterCard?> Function() ensureCardSaved;

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

  CharacterCard? _card;
  CharacterCard? get card => _card;

  // ── Choices ───────────────────────────────────────────────────────────────
  PortraitSource source = PortraitSource.upload;
  bool packEnabled = false;
  bool fullSet = false;

  // ── Applied images ────────────────────────────────────────────────────────
  /// The portrait as applied to the card this session (uploaded or generated);
  /// also the pack's identity base.
  Uint8List? portraitBytes;

  /// Extra uploads applied this session (pack OFF only); null emotion = look.
  final List<({Uint8List bytes, String? emotion})> extraUploads = [];

  // ── Engine catalog (shared Studio config, never a second one) ────────────
  List<({String value, String label})> modelOptions = [];
  bool? connectionOk;
  bool testingConnection = false;
  bool loadingModels = false;

  // ── Vision QC gate ────────────────────────────────────────────────────────
  bool qcVisible = false;
  bool qcKnownSupported = false;
  bool qcEnabled = false;
  bool resolvingVision = false;
  VisionEvalFn? _visionFire;

  // ── Run state ─────────────────────────────────────────────────────────────
  AvatarRunStage stage = AvatarRunStage.idle;
  String statusDetail = '';
  ExpressionPackSession? session;
  ExpressionPackQc? qc;
  int importedCount = 0;
  int flaggedExcluded = 0;
  bool _cancelRequested = false;
  bool _disposed = false;
  Set<String> _existingEmotions = const {};

  /// The one in-flight first-persist (see _ensureCard's single-flight guard).
  Future<bool>? _ensuring;

  bool get running =>
      stage != AvatarRunStage.idle &&
      stage != AvatarRunStage.done &&
      stage != AvatarRunStage.failed;

  // ── Derived gates ─────────────────────────────────────────────────────────
  ImageGenBackend get backend => ImageGenBackend.fromKey(storage.imageGenBackend);
  bool get engineReady => imageGen.isConfigured;

  /// The exact decision the Studio's pack dialog uses (edit slot + ComfyUI
  /// readiness). img2img is the automatic fallback where edit truly isn't.
  bool get packEditModeNow =>
      ImageReferenceResolver.packEditMode(storage.imageGenSettings);

  /// The Edit-tab view for the edit-model row (readiness copy per backend).
  ImageReferenceCapability get editCapability =>
      ImageReferenceResolver.resolveForBackend(
        backend: backend,
        modelName: storage.imageGenSettings.imageGenEditModel,
      );

  /// Pack GENERATION is possible: an engine, a portrait source to build from,
  /// and — remote only — an edit model (remote has no img2img floor).
  bool get packPossible =>
      engineReady &&
      source != PortraitSource.none &&
      (backend != ImageGenBackend.remote || packEditModeNow);

  List<String> get chosenSet =>
      fullSet ? kFullExpressionSet : kCuratedExpressionSet;

  /// Emotions the run would actually generate (existing labels are kept, same
  /// default as the Studio's second-run behavior).
  List<String> get missingEmotions => [
    for (final e in chosenSet)
      if (!_existingEmotions.contains(e)) e,
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
  bool get promptEditable =>
      !running || stage == AvatarRunStage.portraitReview;

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
  Future<void> setQcEnabled(bool v) async {
    if (!v) {
      qcEnabled = false;
      notifyListeners();
      return;
    }
    if (qcKnownSupported) {
      qcEnabled = true;
      notifyListeners();
      return;
    }
    if (resolvingVision) return;
    resolvingVision = true;
    notifyListeners();
    final fire = await resolveVisionFire();
    if (_disposed) return;
    resolvingVision = false;
    _visionFire = fire;
    qcEnabled = fire != null;
    qcKnownSupported = fire != null;
    notifyListeners();
  }

  // ── Init (fire-and-forget from the panel's initState) ────────────────────
  /// One-call init: engine probe + QC gate + (when the host handed over an
  /// already-saved card) the existing-emotion labels for the CTA count.
  Future<void> init() async {
    unawaited(initQcGate());
    unawaited(refreshEngine());
    if (_card?.dbId != null) {
      await _loadExistingEmotions();
      if (!_disposed) notifyListeners();
    }
  }

  /// Hidden/shown per the shipped VisionSupportResolver, WITHOUT probing:
  /// known-unsupported → the toggle doesn't exist; known-supported → shown
  /// (default off); unknown → shown, resolved on toggle.
  Future<void> initQcGate() async {
    final support = await peekVisionSupport();
    if (_disposed) return;
    if (support != null &&
        !support.supported &&
        support.source != VisionSource.unknown) {
      qcVisible = false;
    } else {
      qcVisible = true;
      qcKnownSupported = support?.supported ?? false;
    }
    notifyListeners();
  }

  /// Connection test (local backends) + model catalog for the engine strip
  /// and the edit-model row. Mirrors the Studio settings tab's auto-test.
  Future<void> refreshEngine() async {
    connectionOk = null;
    modelOptions = [];
    if (backend != ImageGenBackend.remote) {
      final url = backendProbeUrl(storage);
      if (url.isEmpty) {
        notifyListeners();
        return;
      }
      testingConnection = true;
      notifyListeners();
      final ok = await imageGen.testLocalConnection(url);
      if (_disposed) return;
      testingConnection = false;
      connectionOk = ok;
      if (!ok) {
        notifyListeners();
        return;
      }
    }
    loadingModels = true;
    notifyListeners();
    final options = await fetchBackendModelOptions(imageGen, storage);
    if (_disposed) return;
    modelOptions = options;
    loadingModels = false;
    notifyListeners();
  }

  // ── Upload paths (apply immediately via the existing plumbing) ───────────
  /// Sets [bytes] as the card's portrait: written over the existing in-app
  /// portrait file IN PLACE (folders key members by its basename) or a fresh
  /// file when none exists, then re-embedded via updateCharacter.
  Future<bool> applyPortrait(Uint8List bytes) async {
    if (!await _ensureCard()) return false;
    final card = _card!;
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
    if (!await _ensureCard()) return false;
    final card = _card!;
    if (emotion == null) {
      await repository.addLook(card.dbId!, card.name, bytes);
    } else {
      await repository.addAvatar(card.dbId!, card.name, bytes, emotion);
      _existingEmotions = {..._existingEmotions, emotion};
    }
    extraUploads.add((bytes: bytes, emotion: emotion));
    if (!_disposed) notifyListeners();
    return true;
  }

  /// Emotion-named ZIP sprite pack (the generation alternative). Returns
  /// (added, unrecognized).
  Future<(int, int)> importExpressionZip(Uint8List zipBytes) async {
    if (!await _ensureCard()) return (0, 0);
    final card = _card!;
    final result = decodeSpritePack(zipBytes);
    var added = 0;
    for (final e in result.entries) {
      await repository.addAvatar(card.dbId!, card.name, e.bytes, e.emotion);
      extraUploads.add((bytes: e.bytes, emotion: e.emotion));
      _existingEmotions = {..._existingEmotions, e.emotion};
      added++;
    }
    if (added > 0 && !storage.expressionEnabled) {
      await storage.setExpressionEnabled(true);
    }
    if (!_disposed) notifyListeners();
    return (added, result.unrecognized);
  }

  // ── The run (portrait → veto gate → pack) ─────────────────────────────────
  Future<void> run() async {
    if (running || ctaLabel == null) return;
    _cancelRequested = false;
    importedCount = 0;
    flaggedExcluded = 0;
    statusDetail = '';
    final wantPortrait = source == PortraitSource.generate;

    _setStage(AvatarRunStage.saving);
    if (!await _ensureCard()) {
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
      if (!await _generatePortrait()) return; // _fail already set on error
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
    if (!await _generatePortrait()) return; // _fail set on error
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
    _cancelRequested = true;
    session?.cancel();
    qc?.cancel();
    notifyListeners();
  }

  /// Library-private notify hook so the `part` extension (which cannot touch
  /// the @protected [notifyListeners]) can broadcast state changes.
  void _notify() => notifyListeners();

  @override
  void dispose() {
    _disposed = true;
    session?.cancel();
    session?.removeListener(_notify);
    session?.dispose();
    qc?.cancel();
    qc?.removeListener(_notify);
    qc?.dispose();
    promptController.dispose();
    super.dispose();
  }
}
