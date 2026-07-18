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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/image_gen_service.dart'
    show ImageGenMode;
import 'package:front_porch_ai/services/image_prompt/image_gen_context.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt_builder.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The heart of pre-gen control (per Stage 3 spec).
/// Editable main prompt (prefilled from builder), pills/sections for distilled
/// source transparency + quick tweaks, negative editor for *this* gen.
class PromptWorkspace extends StatefulWidget {
  final String prompt;
  final String negative;
  final ImageGenContext ctx;
  final ImagePromptBuilder builder;
  final String paradigm;
  final bool llmAvailable;
  final bool isBusy;
  final ValueChanged<String> onPromptChanged;
  final ValueChanged<String> onNegativeChanged;
  final VoidCallback onCraftLlm;

  const PromptWorkspace({
    super.key,
    required this.prompt,
    required this.negative,
    required this.ctx,
    required this.builder,
    required this.paradigm,
    required this.llmAvailable,
    required this.isBusy,
    required this.onPromptChanged,
    required this.onNegativeChanged,
    required this.onCraftLlm,
  });

  @override
  State<PromptWorkspace> createState() => _PromptWorkspaceState();
}

class _PromptWorkspaceState extends State<PromptWorkspace> {
  // Persistent controllers — owned by State, created once. Recreating them per
  // build (the old pattern) reset the caret to offset 0 on every keystroke, so
  // each character landed at the start and the prompt came out reversed.
  late final TextEditingController _promptController;
  late final TextEditingController _negativeController;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: widget.prompt);
    _negativeController = TextEditingController(text: widget.negative);
  }

  @override
  void didUpdateWidget(PromptWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Push parent changes into the controllers ONLY when they differ from what
    // the field already holds — i.e. an external rewrite (Craft / Refresh with
    // LLM), not the user's own typing (where widget.prompt already mirrors the
    // controller). Assigning .text unconditionally would collapse the caret to
    // offset 0 again; here we set the caret to the end after an external swap.
    if (widget.prompt != _promptController.text) {
      _promptController.value = TextEditingValue(
        text: widget.prompt,
        selection: TextSelection.collapsed(offset: widget.prompt.length),
      );
    }
    if (widget.negative != _negativeController.text) {
      _negativeController.value = TextEditingValue(
        text: widget.negative,
        selection: TextSelection.collapsed(offset: widget.negative.length),
      );
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + craft action
          // Flexibles on label + button to prevent RenderFlex overflow in constrained test rigs / narrow windows
          // (pre-existing row at 282px allocation; our added type selector + slider above makes it tighter in harness).
          Row(
            children: [
              Flexible(
                child: Text(
                  'Prompt (editable before generation)',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.llmAvailable)
                Flexible(
                  fit: FlexFit.loose,
                  child: TextButton.icon(
                    onPressed: widget.isBusy ? null : widget.onCraftLlm,
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text('✨ Write it for me'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.resolve(
                        context,
                        AppColors.formMasterAccent,
                        AppColors.formMasterAccent,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Main editable prompt field (first-class control). Uses the
          // persistent State-owned controller; Craft/Refresh updates flow in
          // via didUpdateWidget (caret moved to end), and typing is preserved.
          TextField(
            controller: _promptController,
            onChanged: widget.onPromptChanged,
            enabled: !widget.isBusy,
            maxLines: 5,
            minLines: 3,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText:
                  'Describe what you want (optional), tap ✨ Write it for me to have '
                  'the AI draft the prompt from your scene, then Generate.',
              hintStyle: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppColors.resolve(
                    context,
                    AppColors.formMasterAccent,
                    AppColors.formMasterAccent,
                  ),
                  width: 1.5,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Distilled sources (pills/sections for transparency; quick append actions)
          _buildSourcePills(context),

          const SizedBox(height: 12),

          // Per-generation negative (starts from global, user controlled for this run)
          Text(
            'Negative prompt (for this generation)',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _negativeController,
            onChanged: widget.onNegativeChanged,
            enabled: !widget.isBusy,
            maxLines: 2,
            minLines: 1,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText:
                  'blurry, lowres, deformed, watermark... (edits only this generation)',
              hintStyle: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              contentPadding: const EdgeInsets.all(8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
            ),
          ),

          const SizedBox(height: 8),
          Text(
            'Provenance: high-quality output from ImagePromptBuilder (Stage 2) using card + scene context. Edit freely.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  String _cleanForPill(String text) {
    if (text.isEmpty) return text;
    // Strip think blocks (completed and unclosed tails) and auto-imported card meta
    // so the source pills never show the garbage the user complained about (<think>, "Auto-imported from character card: Aerin", etc.).
    text = text.replaceAll(
      RegExp(r'<\/?think>.*?<\/think>', dotAll: true, caseSensitive: false),
      '',
    );
    final idx = text.toLowerCase().lastIndexOf('<think>');
    if (idx != -1) {
      text = text.substring(0, idx);
    }
    text = text.replaceAll(
      RegExp(r'<\/?think[^>]*>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'Auto-imported from character card:.*?(?:\n|$)',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return text;
  }

  Widget _buildSourcePills(BuildContext context) {
    final ctx = widget.ctx;
    final pills = <Widget>[];
    if (ctx.characterDescription != null &&
        ctx.characterDescription!.trim().isNotEmpty) {
      pills.add(
        _pill(
          context,
          'Appearance from card',
          ctx.effectiveCharacterAppearance,
        ),
      );
    }
    if (ctx.lastMessage != null &&
        ctx.lastMessage!.trim().isNotEmpty &&
        ctx.mode != ImageGenMode.customPrompt) {
      final cleaned = _cleanForPill(ctx.resolveMacros(ctx.lastMessage!));
      if (cleaned.isNotEmpty) {
        pills.add(
          _pill(
            context,
            'Action / scene from last message',
            ImageGenContext.truncate(cleaned, 120),
          ),
        );
      }
    }
    if (ctx.scenario != null && ctx.scenario!.trim().isNotEmpty) {
      final cleaned = _cleanForPill(ctx.resolveMacros(ctx.scenario!));
      if (cleaned.isNotEmpty) {
        pills.add(
          _pill(
            context,
            'Setting / scenario',
            ImageGenContext.truncate(cleaned, 100),
          ),
        );
      }
    }
    if (ctx.worldInfo != null && ctx.worldInfo!.trim().isNotEmpty) {
      final cleaned = _cleanForPill(ctx.resolveMacros(ctx.worldInfo!));
      if (cleaned.isNotEmpty) {
        pills.add(
          _pill(
            context,
            'World / atmosphere',
            ImageGenContext.truncate(cleaned, 100),
          ),
        );
      }
    }
    // Surface richer ctx data in provenance pills (currentExpression is already
    // merged into appearance; show group speaker + time/lighting for transparency).
    if (ctx.isGroupNonObserver &&
        ctx.currentSpeakerId != null &&
        ctx.currentSpeakerId!.trim().isNotEmpty) {
      pills.add(_pill(context, 'Group speaker focus', ctx.currentSpeakerId!));
    }
    if (ctx.timeOfDay != null && ctx.timeOfDay!.trim().isNotEmpty) {
      pills.add(_pill(context, 'Time of day', ctx.timeOfDay!));
    }
    if (ctx.lightingHint != null && ctx.lightingHint!.trim().isNotEmpty) {
      pills.add(_pill(context, 'Lighting hint', ctx.lightingHint!));
    }
    if (pills.isEmpty) {
      return Text(
        'Sources distilled by builder (edit main prompt to emphasize or override).',
        style: TextStyle(color: AppColors.textTertiary(context), fontSize: 10),
      );
    }
    return Wrap(spacing: 6, runSpacing: 4, children: pills);
  }

  Widget _pill(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '$label: ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
