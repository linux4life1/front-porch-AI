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
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/expression_pack_qc.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'studio_widgets.dart';

part 'expression_pack_dialog.base.dart';
part 'expression_pack_launch.dart';
part 'expression_pack_dialog.view.dart';
part 'expression_pack_dialog.qc.dart';

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
    this.note,
  }) : embedded = false,
       onImported = null,
       onSessionChanged = null,
       onDiscard = null;

  const ExpressionPackDialog.workspace({
    super.key,
    this.onImported,
    this.onSessionChanged,
    this.onDiscard,
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
    this.note,
  }) : embedded = true;

  final bool embedded;
  final VoidCallback? onImported;
  final ValueChanged<bool>? onSessionChanged;
  final VoidCallback? onDiscard;

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

  /// Shown in the setup when the base was converted to a PNG.
  final String? note;

  static Future<bool> launch(
    BuildContext context, {
    required String characterDbId,
    required String characterName,
    required CharacterRepository repository,
    required Uint8List? candidateBase,
    required String basePrompt,
    required String negativePrompt,
  }) => _launchExpressionPack(
    context,
    characterDbId: characterDbId,
    characterName: characterName,
    repository: repository,
    candidateBase: candidateBase,
    basePrompt: basePrompt,
    negativePrompt: negativePrompt,
  );

  @override
  State<ExpressionPackDialog> createState() => ExpressionPackDialogState();
}

class ExpressionPackDialogState extends State<ExpressionPackDialog> {
  ExpressionPackSession? _session;
  bool _checkingWorkflow = false;
  bool _replaceExisting = true;
  bool _cancelRequested = false;
  bool _importing = false;
  bool _imported = false;

  /// The base portrait, encoded once and shared by every vision call.
  late final String _baseB64 = base64Encode(widget.baseImage);

  /// Vision QC controller for the grid; a new run replaces (and disposes) the
  /// previous one. Null until the first "Vision check".
  ExpressionPackQc? _qc;
  bool _resolvingVision = false;
  void _setDialogState(VoidCallback fn) => setState(fn);

  @override
  void dispose() {
    final session = _session;
    if (session != null) expressionPackBoard.release(session);
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
  Future<void> _start({
    required bool fullSet,
    required double denoise,
    required bool replaceExisting,
    required bool skipExisting,
  }) async {
    if (_checkingWorkflow || widget.imageGen.isGenerating) return;
    if (!_canOwnBoard()) return;
    setState(() => _checkingWorkflow = true);
    widget.onSessionChanged?.call(true);
    try {
      _replaceExisting = replaceExisting;
      final chosen = fullSet ? kFullExpressionSet : kCuratedExpressionSet;
      final emotions = skipExisting
          ? [
              for (final e in chosen)
                if (!widget.existingEmotions.contains(e)) e,
            ]
          : chosen;
      final plan = await planExpressionPack(widget.storage);
      if (!mounted) return;
      if (!plan.canStart ||
          (widget.embedded && !plan.edit && widget.basePrompt.trim().isEmpty)) {
        setState(() => _checkingWorkflow = false);
        widget.onSessionChanged?.call(false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              plan.refusal ?? 'Add a pack description before generating.',
            ),
            duration: const Duration(seconds: 10),
          ),
        );
        return;
      }
      if (!_canOwnBoard()) {
        setState(() => _checkingWorkflow = false);
        widget.onSessionChanged?.call(false);
        return;
      }
      final flight = await beginExpressionPack(
        imageGen: widget.imageGen,
        plan: plan,
        emotions: emotions,
        basePrompt: '${widget.basePrompt}, $kExpressionFraming',
        negativePrompt: widget.negativePrompt,
        denoise: denoise,
        size: '${widget.baseWidth}x${widget.baseHeight}',
        baseImage: widget.baseImage,
        characterName: widget.characterName,
        characterId: widget.characterDbId,
        replaceExisting: replaceExisting,
        onCancelled: () {
          if (mounted) setState(() => _cancelRequested = true);
        },
      );
      if (!mounted) {
        final abandoned = flight.session;
        if (abandoned != null) {
          abandoned.cancel();
          expressionPackBoard.release(abandoned);
          abandoned.dispose();
        }
        return;
      }
      setState(() {
        _checkingWorkflow = false;
        _session = flight.session;
        widget.onSessionChanged?.call(_session != null);
      });
      if (flight.session == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              flight.busy
                  ? kAlreadyGeneratingMessage
                  : (flight.error ?? 'The expression pack could not start.'),
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _checkingWorkflow = false);
      widget.onSessionChanged?.call(false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Pack could not start: $error')));
    }
  }

  bool _canOwnBoard() {
    final other = expressionPackBoard.run;
    if (!widget.embedded ||
        other == null ||
        identical(other.session, _session)) {
      return true;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Another screen has an expression pack. Import or discard that pack on its original screen before starting here.',
        ),
      ),
    );
    return false;
  }

  /// Runs what is still pending, under the same hold of the generation lock.
  Future<void> _resume(ExpressionPackSession session) async {
    if (widget.imageGen.isGenerating || _imported) return;
    setState(() => _cancelRequested = false);
    final names = await widget.imageGen.startExpressionPack(
      [
        for (final slot in session.slots)
          if (slot.state == ExpressionSlotState.pending) slot.emotion,
      ],
      (_) async {
        await session.run();
        return const <String>[];
      },
    );
    if (!mounted) return;
    if (names == null) {
      setState(() => _cancelRequested = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(kAlreadyGeneratingMessage)));
    }
  }

  Future<void> _import() async {
    if (_importing || _imported) return;
    final session = _session!;
    setState(() => _importing = true);
    try {
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
      _imported = true;
      final run = expressionPackBoard.run;
      if (identical(run?.session, session)) run!.imported = count;
      if (widget.embedded) {
        widget.onImported?.call();
        setState(() => _importing = false);
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $error')));
    }
  }

  bool get hasPack => _session != null || _checkingWorkflow;

  Future<bool> confirmDiscard() async {
    if (_importing || _checkingWorkflow) return false;
    if (_session == null) return true;
    final discard = await showWarmDialog<bool>(
      context,
      title: 'Discard expression pack?',
      icon: Icons.delete_outline,
      content: const WarmDialogText(
        'Stop this pack and discard its results? Imported expressions remain in the library.',
      ),
      actions: [
        warmDialogCancel(context, label: 'Keep pack'),
        warmDialogConfirm(
          context,
          label: 'Discard',
          destructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (discard != true || !mounted) return false;
    _session?.cancel();
    return true;
  }

  /// Header X: confirm when a run is in flight (cancel stops after the
  /// current image; the session is dispose-safe).
  Future<void> _close() async {
    if (widget.embedded) {
      if (await confirmDiscard()) widget.onDiscard?.call();
      return;
    }
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
  Widget build(BuildContext context) => _buildPack(context);
}
