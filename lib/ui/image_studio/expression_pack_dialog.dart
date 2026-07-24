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
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/capability/image_reference_resolver.dart';
import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/expression_pack_qc.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/services/image_prompt/expression_prompts.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'expression_pack_grid.dart';
import 'expression_pack_setup.dart';
import 'vision_gate.dart';

/// The Expression-pack flow: turn one base portrait into a labeled set of
/// expression avatars — edit-first (instruction edits off the base) with an
/// automatic img2img fallback where edit truly doesn't exist. [launch] runs
/// the pre-flight (backend guard, base-image resolution, and automatic
/// aspect-preserving size normalization — no crop step) and then shows this
/// two-step dialog (setup, then the live generation grid).
class ExpressionPackDialog extends StatefulWidget {
  const ExpressionPackDialog._({
    required this.characterDbId,
    required this.characterName,
    required this.repository,
    required this.storage,
    required this.imageGen,
    required this.baseImage,
    required this.baseWidth,
    required this.baseHeight,
    required this.basePrompt,
    required this.negativePrompt,
    required this.existingEmotions,
  });

  final String characterDbId;
  final String characterName;
  final CharacterRepository repository;
  final StorageService storage;
  final ImageGenService imageGen;

  /// The normalized base portrait; every slot generates at exactly
  /// [baseWidth]x[baseHeight], so the pack matches the avatar's aspect.
  final Uint8List baseImage;
  final int baseWidth;
  final int baseHeight;
  final String basePrompt;
  final String negativePrompt;

  /// Emotion labels this character ALREADY has expression images for —
  /// a second pack run (Starter first, Full later) keeps them by default
  /// and only generates the missing ones.
  final Set<String> existingEmotions;

  /// Run the whole flow. Returns true iff a pack was imported.
  static Future<bool> launch(
    BuildContext context, {
    required String characterDbId,
    required String characterName,
    required CharacterRepository repository,
    required Uint8List? candidateBase,
    required String basePrompt,
    required String negativePrompt,
  }) async {
    // Capture providers before any async gap.
    final storage = Provider.of<StorageService>(context, listen: false);
    final imageGen = Provider.of<ImageGenService>(context, listen: false);

    // Remote APIs have no img2img here, so a remote pack runs entirely
    // through the provider's image-EDIT endpoint — which needs an
    // edit-capable model in the EDIT slot. Local backends always have the
    // img2img floor, so they pass regardless.
    if (ImageGenBackend.fromKey(storage.imageGenSettings.imageGenBackend) ==
            ImageGenBackend.remote &&
        !ImageReferenceResolver.packEditMode(storage.imageGenSettings)) {
      await showWarmDialog(
        context,
        title: 'Edit model needed',
        icon: Icons.theater_comedy,
        accent: AppColors.formMasterAccent,
        content: const WarmDialogText(
          'On a remote API the pack generates through the provider\'s '
          'image-edit endpoint, so it needs an edit-capable model (e.g. '
          'qwen-image-max-edit) in the Edit tab\'s model slot. Pick one '
          'there — or switch to a local backend (A1111, ComfyUI, or Draw '
          'Things), which can always fall back to img2img.',
        ),
        actions: [warmDialogCancel(context, label: 'Got it')],
      );
      return false;
    }

    // Base portrait: the studio's current result/reference when it has one
    // (style-matched to what the user is making right now), else the
    // character's existing avatar (prime expression avatar, falling back to
    // the main card portrait).
    final base =
        candidateBase ??
        await _primeAvatarBytes(
          repository,
          storage,
          characterDbId,
          characterName,
        );
    if (!context.mounted) return false;
    if (base == null) {
      await showWarmDialog(
        context,
        title: 'No base portrait',
        icon: Icons.theater_comedy,
        accent: AppColors.formMasterAccent,
        content: const WarmDialogText(
          'This character has no avatar image yet — generate a portrait in '
          'the Studio (or set a card avatar) first; the pack is built from '
          'a base image.',
        ),
        actions: [warmDialogCancel(context, label: 'Got it')],
      );
      return false;
    }

    // Fully automatic base prep — no crop step (maintainer decision: zero
    // friction; the pack must simply match the avatar's shape). The
    // normalizer preserves the source aspect ratio, so the generated
    // expressions look like the avatar the user already sees in the sidebar.
    // Anyone wanting different framing can pick a pre-cropped reference
    // image in the Studio first.
    final normalized = normalizePackBase(base);
    if (!context.mounted) return false;
    if (normalized == null) {
      await showWarmDialog(
        context,
        title: 'Unreadable image',
        icon: Icons.broken_image_outlined,
        content: const WarmDialogText(
          'That image could not be decoded — try a different portrait.',
        ),
        actions: [warmDialogCancel(context, label: 'Got it')],
      );
      return false;
    }

    // Labels the character already has — lets the setup default to
    // generating only the MISSING emotions on a second run, instead of
    // regenerating (and, with replace on, overwriting) the kept ones.
    final existingEmotions = (await repository.getAvatarImages(characterDbId))
        .map((a) => (a.label ?? '').toLowerCase())
        .where((l) => l.isNotEmpty)
        .toSet();
    if (!context.mounted) return false;

    final imported = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExpressionPackDialog._(
        characterDbId: characterDbId,
        characterName: characterName,
        repository: repository,
        storage: storage,
        imageGen: imageGen,
        baseImage: normalized.bytes,
        baseWidth: normalized.width,
        baseHeight: normalized.height,
        basePrompt: basePrompt,
        negativePrompt: negativePrompt,
        existingEmotions: existingEmotions,
      ),
    );
    return imported == true;
  }

  /// The best on-disk portrait for [characterDbId]: the prime (else first)
  /// expression avatar when any exist, else the character's MAIN card avatar
  /// ([CharacterCard.imagePath]). The card avatar is the load-bearing case —
  /// a character about to get their first expression pack has no expression
  /// images yet (creating them is the whole point), but almost always has a
  /// card portrait. Null only when the character has no image at all.
  static Future<Uint8List?> _primeAvatarBytes(
    CharacterRepository repository,
    StorageService storage,
    String characterDbId,
    String characterName,
  ) async {
    CharacterCard? card;
    for (final c in repository.characters) {
      if (c.dbId == characterDbId) {
        card = c;
        break;
      }
    }

    final avatars = await repository.getAvatarImages(characterDbId);
    if (avatars.isNotEmpty) {
      // primeAvatarIndex is 1-based; clamp handles stale indices.
      final primeIdx = ((card?.primeAvatarIndex ?? 1) - 1).clamp(
        0,
        avatars.length - 1,
      );
      final dirPath = storage.characterAvatarDir(characterName).path;
      for (final avatar in [avatars[primeIdx], ...avatars]) {
        final file = avatar.file(dirPath);
        if (await file.exists()) return file.readAsBytes();
      }
    }

    final imagePath = card?.imagePath;
    if (imagePath != null && imagePath.isNotEmpty) {
      final file = File(imagePath);
      if (await file.exists()) return file.readAsBytes();
    }
    return null;
  }

  @override
  State<ExpressionPackDialog> createState() => _ExpressionPackDialogState();
}

class _ExpressionPackDialogState extends State<ExpressionPackDialog> {
  ExpressionPackSession? _session;
  bool _replaceExisting = true;
  bool _cancelRequested = false;
  bool _importing = false;

  /// The base portrait, encoded once and shared by every vision call.
  late final String _baseB64 = base64Encode(widget.baseImage);

  /// Vision QC controller for the grid; a new run replaces (and disposes) the
  /// previous one. Null until the first "Vision check".
  ExpressionPackQc? _qc;
  bool _resolvingVision = false;

  @override
  void dispose() {
    _session?.cancel();
    _session?.dispose();
    _qc?.cancel();
    _qc?.dispose();
    super.dispose();
  }

  /// Grid "Vision check": QC every generated image against the base portrait.
  /// Advisory only — badges and the explicit "Uncheck flagged" action. The
  /// resolve-or-explain step is the shared [resolveVisionFireWithExplainer]
  /// (click-time only, same gate as the creator panel).
  Future<void> _runVisionCheck() async {
    final session = _session;
    if (session == null || _resolvingVision || (_qc?.isRunning ?? false)) {
      return;
    }
    setState(() => _resolvingVision = true);
    final fire = await resolveVisionFireWithExplainer(context);
    if (!mounted) return;
    setState(() => _resolvingVision = false);
    if (fire == null) return;
    final previous = _qc;
    previous?.cancel();
    final qc = ExpressionPackQc(
      slots: session.slots,
      baseImageB64: _baseB64,
      fire: fire,
    );
    setState(() => _qc = qc);
    // Safe immediate disposal: the grid's ListenableBuilder unsubscribes from
    // the old controller during the rebuild, and ChangeNotifier explicitly
    // permits removeListener after dispose.
    previous?.dispose();
    unawaited(qc.run());
  }

  void _start({
    required bool fullSet,
    required double denoise,
    required bool replaceExisting,
    required bool skipExisting,
  }) {
    _replaceExisting = replaceExisting;
    final chosen = fullSet ? kFullExpressionSet : kCuratedExpressionSet;
    final emotions = skipExisting
        ? [
            for (final e in chosen)
              if (!widget.existingEmotions.contains(e)) e,
          ]
        : chosen;
    // Edit-first: when the active backend + the EDIT-slot model can
    // instruction-edit, drive each emotion through the EDIT path (identity
    // pinned by the base portrait) instead of img2img. The decision is the
    // ONE shared [ImageReferenceResolver.packEditMode] (also used by the
    // creator's Portrait & Avatars panel) — resolver supportsEdit over the
    // edit slot + the Edit tab's ComfyUI workflow-readiness gate.
    final editMode = ImageReferenceResolver.packEditMode(
      widget.storage.imageGenSettings,
    );
    final session = ExpressionPackSession(
      emotions: emotions,
      basePrompt: '${widget.basePrompt}, $kExpressionFraming',
      negativePrompt: widget.negativePrompt,
      denoise: denoise,
      editMode: editMode,
      generate:
          ({
            required String prompt,
            required String negativePrompt,
            required int seed,
            required double denoise,
          }) => widget.imageGen.generateImage(
            prompt: prompt,
            negativePrompt: negativePrompt,
            size: '${widget.baseWidth}x${widget.baseHeight}',
            referenceImage: widget.baseImage,
            seed: seed,
            denoise: denoise,
            // Edit path when available: the reference is read as conditioning
            // and the strength slider becomes the edit strength; else img2img.
            intent: editMode ? StudioIntent.edit : StudioIntent.create,
            editStrength: editMode ? denoise : null,
          ),
    );
    setState(() => _session = session);
    unawaited(session.run());
  }

  Future<void> _import() async {
    final session = _session!;
    setState(() => _importing = true);
    final count = await ExpressionPackImporter.importPack(
      repository: widget.repository,
      storage: widget.storage,
      characterDbId: widget.characterDbId,
      characterName: widget.characterName,
      slots: session.slots,
      replaceSameLabel: _replaceExisting,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Imported $count expressions for ${widget.characterName} — '
          'expressions enabled',
        ),
      ),
    );
    Navigator.of(context).pop(true);
  }

  /// Header X: confirm when a run is in flight (cancel stops after the
  /// current image; the session is dispose-safe).
  Future<void> _close() async {
    final session = _session;
    if (session != null && session.isRunning) {
      final stop = await showWarmDialog<bool>(
        context,
        title: 'Stop generating?',
        icon: Icons.stop_circle_outlined,
        content: const WarmDialogText(
          'The pack is still generating. Stop after the current image and '
          'discard the results?',
        ),
        actions: [
          warmDialogCancel(context, label: 'Keep going'),
          warmDialogConfirm(
            context,
            label: 'Stop',
            destructive: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
      if (stop != true || !mounted) return;
      session.cancel();
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.of(context).size.height * 0.94,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            Flexible(
              child: session == null
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ExpressionPackSetup(
                        baseImage: widget.baseImage,
                        characterName: widget.characterName,
                        existingEmotions: widget.existingEmotions,
                        onCancel: () => Navigator.of(context).pop(false),
                        onStart: _start,
                      ),
                    )
                  : ExpressionPackGrid(
                      session: session,
                      imageGen: widget.imageGen,
                      cancelRequested: _cancelRequested,
                      importing: _importing,
                      qc: _qc,
                      resolvingVision: _resolvingVision,
                      onVisionCheck: _runVisionCheck,
                      onCancel: () {
                        setState(() => _cancelRequested = true);
                        session.cancel();
                      },
                      onResume: () {
                        setState(() => _cancelRequested = false);
                        unawaited(session.run());
                      },
                      onImport: _import,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        children: [
          Icon(Icons.theater_comedy, color: AppColors.formMasterAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Expression pack — ${widget.characterName}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: AppColors.iconSecondary(context)),
            onPressed: _close,
          ),
        ],
      ),
    );
  }
}
