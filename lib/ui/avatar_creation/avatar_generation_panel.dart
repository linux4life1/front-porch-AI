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

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/vision_support_resolver.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/image_studio/vision_gate.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'avatar_creation_controller.dart';
import 'expressions_section.dart';
import 'portrait_section.dart';

part 'avatar_generation_panel.progress.dart';

/// The ONE shared "Portrait & Avatars" panel (phase #12), hosted by BOTH
/// creators — the manual wizard's final step and the AI Character Creator's
/// review screen. Portrait section + independent Expressions section + the
/// generate CTA and live progress. All engine controls are views over Image
/// Studio's config; all results land via the existing gallery plumbing.
class AvatarGenerationPanel extends StatefulWidget {
  const AvatarGenerationPanel({
    super.key,
    required this.ensureCardSaved,
    required this.initialPrompt,
    this.card,
    this.onBusyChanged,
  });

  /// Host guarantee: returns a persisted card (dbId set), saving it first if
  /// needed, or null on failure. Called before ANY image lands.
  final Future<CharacterCard?> Function() ensureCardSaved;

  /// Portrait-prompt seed from the host's appearance/description fields.
  final String initialPrompt;

  /// Already-saved card, when the host saved before showing the panel.
  final CharacterCard? card;

  /// Fires on run start/stop so the host can lock its own exits (e.g. the
  /// manual wizard's Done) — leaving mid-run disposes the panel and drops
  /// whatever the engine was still finishing.
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<AvatarGenerationPanel> createState() => _AvatarGenerationPanelState();
}

class _AvatarGenerationPanelState extends State<AvatarGenerationPanel> {
  late final AvatarCreationController _c;
  bool _lastBusy = false;

  void _reportBusy() {
    if (_c.running == _lastBusy) return;
    _lastBusy = _c.running;
    widget.onBusyChanged?.call(_lastBusy);
  }

  @override
  void initState() {
    super.initState();
    final storage = Provider.of<StorageService>(context, listen: false);
    _c = AvatarCreationController(
      ensureCardSaved: widget.ensureCardSaved,
      repository: Provider.of<CharacterRepository>(context, listen: false),
      storage: storage,
      imageGen: Provider.of<ImageGenService>(context, listen: false),
      resolveVisionFire: () async {
        if (!mounted) return null;
        return resolveVisionFireWithExplainer(context);
      },
      peekVisionSupport: () {
        final llm = Provider.of<LLMProvider>(context, listen: false);
        return VisionSupportResolver.instance.peekForActiveLlm(
          backend: llm.activeBackend,
          storage: storage,
        );
      },
      initialPrompt: widget.initialPrompt,
      card: widget.card,
    );
    _c.addListener(_reportBusy);
    _c.init();
  }

  @override
  void dispose() {
    _c.removeListener(_reportBusy);
    // A host that outlives the panel must never be stuck on busy == true.
    if (_lastBusy) widget.onBusyChanged?.call(false);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Storage is in the merge so gear-dialog edits (backend/model/URL) and
    // slot changes repaint the strip and the edit-model row live.
    final storage = Provider.of<StorageService>(context, listen: false);
    return AnimatedBuilder(
      animation: Listenable.merge([_c, _c.promptController, storage]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PortraitSection(controller: _c),
          // Veto gate: its own card right above the expressions, so the
          // portrait is reviewed (and regenerated) before the pack config —
          // not buried under it in the bottom progress card.
          if (_c.stage == AvatarRunStage.portraitReview) ...[
            const SizedBox(height: 16),
            _reviewCard(context),
          ],
          const SizedBox(height: 16),
          ExpressionsSection(controller: _c),
          const SizedBox(height: 16),
          if (_c.ctaLabel != null && !_c.running) _cta(context),
          // Live progress during an active run / terminal state — never the
          // review pause, whose card sits above the expressions instead.
          if (_c.stage != AvatarRunStage.idle &&
              _c.stage != AvatarRunStage.portraitReview) ...[
            const SizedBox(height: 14),
            _progress(context),
          ],
        ],
      ),
    );
  }

  Widget _cta(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: _c.canRun ? _c.run : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.formMasterAccent,
            foregroundColor: AppColors.onChaosAccent,
            disabledBackgroundColor: AppColors.surfaceContainerOf(context),
            disabledForegroundColor: AppColors.textTertiary(context),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            _c.ctaLabel!,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Runs in order, cancel anytime — whatever finished stays in the '
          'gallery.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
