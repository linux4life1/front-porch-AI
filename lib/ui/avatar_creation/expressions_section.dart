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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/image_prompt/expression_prompts.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_io.dart';
import 'package:front_porch_ai/ui/image_studio/model_slot_dropdown.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'avatar_creation_controller.dart';

/// "Expressions — independent of how the portrait got here": the pack toggle
/// + the Studio's two presets verbatim (8 base / all 28), the capability-gated
/// Vision QC toggle, the EDIT-model row (a view over the SAME edit slot the
/// Studio's Edit tab owns, with its readiness semantics per backend), and the
/// upload/ZIP alternative.
class ExpressionsSection extends StatelessWidget {
  const ExpressionsSection({super.key, required this.controller});

  final AvatarCreationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final packOn = c.packEnabled && c.packPossible;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EXPRESSIONS — INDEPENDENT OF THE PORTRAIT SOURCE',
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _label(context, 'Generate pack'),
              Switch(
                value: packOn,
                activeTrackColor: AppColors.formMasterAccent,
                onChanged: (c.packPossible && !c.running)
                    ? c.setPackEnabled
                    : null,
              ),
              if (packOn) _presetDropdown(context, c),
              if (packOn && c.qcVisible) ...[
                const SizedBox(width: 4),
                _label(context, 'Vision QC'),
                c.resolvingVision
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.formMasterAccent,
                        ),
                      )
                    : Switch(
                        value: c.qcEnabled,
                        activeTrackColor: AppColors.formMasterAccent,
                        onChanged: c.running ? null : c.setQcEnabled,
                      ),
              ],
            ],
          ),
          if (packOn) ...[const SizedBox(height: 8), _editModelRow(context, c)],
          if (!c.packPossible && c.backend == ImageGenBackend.remote && c.engineReady) ...[
            const SizedBox(height: 8),
            Text(
              'On a remote API the pack runs through the provider\'s '
              'image-edit endpoint — pick an edit-capable model (e.g. '
              'qwen-image-max-edit) in the Edit model slot to enable it.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _footer(context, c, packOn),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 10.5,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w700,
      color: AppColors.textTertiary(context),
    ),
  );

  Widget _presetDropdown(BuildContext context, AvatarCreationController c) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<bool>(
        value: c.fullSet,
        dropdownColor: AppColors.surfaceContainerOf(context),
        style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12.5),
        items: [
          DropdownMenuItem(
            value: false,
            child: Text('${kCuratedExpressionSet.length} base emotions'),
          ),
          DropdownMenuItem(
            value: true,
            child: Text('all ${kFullExpressionSet.length}'),
          ),
        ],
        onChanged: c.running ? null : (v) => c.setFullSet(v ?? false),
      ),
    );
  }

  /// The edit-model row — the Studio's Edit-tab setup, shown here. One config.
  Widget _editModelRow(BuildContext context, AvatarCreationController c) {
    switch (c.backend) {
      case ImageGenBackend.drawThings:
      case ImageGenBackend.remote:
        final options = c.backend == ImageGenBackend.remote
            // Remote edit models are an explicit allowlist.
            ? [
                for (final o in c.modelOptions)
                  if (remoteEditSpec(o.value) != null) o,
              ]
            : c.modelOptions;
        final slotValue = c.storage.imageGenSettings.imageGenEditModel;
        final shown = options.isNotEmpty
            ? options
            : (slotValue.isNotEmpty
                  ? [(value: slotValue, label: slotValue)]
                  : const <({String value, String label})>[]);
        final ready = c.editCapability.supportsEdit;
        return Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _label(context, 'Edit model'),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: shown.isEmpty
                  ? Text(
                      c.backend == ImageGenBackend.remote
                          ? 'No edit-capable models in this provider\'s list.'
                          : 'Models appear once the engine is connected.',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 11,
                      ),
                    )
                  : ModelSlotDropdown(
                      settings: c.storage.imageGenSettings,
                      editSlot: true,
                      keyPrefix: 'creator-edit-model',
                      fontSize: 12,
                      decoration: InputDecoration(
                        hintText: 'Pick an edit model',
                        hintStyle: TextStyle(
                          color: AppColors.textTertiary(context),
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceContainerOf(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        isDense: true,
                      ),
                      options: shown,
                    ),
            ),
            _readiness(
              context,
              ok: ready,
              text: ready
                  ? 'Ready'
                  : c.backend == ImageGenBackend.remote
                  ? 'Pick an edit model'
                  : 'img2img fallback',
            ),
          ],
        );
      case ImageGenBackend.comfyUi:
        final ready = c.packEditModeNow;
        return Row(
          children: [
            _label(context, 'Edit workflow'),
            const SizedBox(width: 10),
            _readiness(
              context,
              ok: ready,
              text: ready
                  ? 'Ready — ${c.storage.imageGenSettings.comfyEditWorkflowId}'
                  : 'Not set up (img2img fallback) — configure it in Image '
                        'Studio → Edit',
            ),
          ],
        );
      case ImageGenBackend.a1111:
        return Text(
          'img2img fallback — A1111 can\'t run instruction-edit models; the '
          'pack still works, identity anchored by the base portrait.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
            height: 1.35,
          ),
        );
    }
  }

  Widget _readiness(BuildContext context, {required bool ok, required String text}) {
    // logReady = the app-wide green "ready" status hue (AppColors const).
    final color = ok ? AppColors.logReady : AppColors.formMasterAccent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ok ? Icons.check_circle : Icons.info_outline, size: 13, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  Widget _footer(BuildContext context, AvatarCreationController c, bool packOn) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          packOn
              ? 'Works from an uploaded portrait too — the pack only needs a '
                    'base image. Edit-first, same as the Studio; extra looks '
                    'stay upload-only (craft them in Image Studio → "Save to '
                    'gallery").'
              : 'Upload expression images instead: tag uploads above with an '
                    'emotion, or import an emotion-named ZIP sprite pack.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
            height: 1.4,
          ),
        ),
        if (!packOn) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: c.running ? null : () => _importZip(context, c),
            icon: const Icon(Icons.folder_zip_outlined, size: 15),
            label: const Text('Import ZIP', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.formMasterAccent,
              side: const BorderSide(color: AppColors.formMasterAccent),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _importZip(BuildContext context, AvatarCreationController c) async {
    final zipBytes = await pickZipBytes();
    if (zipBytes == null || !context.mounted) return;
    final (added, unrecognized) = await c.importExpressionZip(zipBytes);
    if (!context.mounted) return;
    final message = added > 0
        ? 'Imported $added expression image${added == 1 ? '' : 's'}'
              '${unrecognized > 0 ? ' · $unrecognized unrecognized' : ''}.'
        : 'No emotion-named images found in that ZIP.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
