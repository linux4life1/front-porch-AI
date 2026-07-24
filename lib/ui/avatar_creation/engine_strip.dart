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

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/ui/dialogs/image_gen_settings_dialog.dart';
import 'package:front_porch_ai/ui/image_studio/model_slot_dropdown.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'avatar_creation_controller.dart';

/// Compact mirror of Image Studio's engine controls — backend picker, live
/// connection dot, Test, CREATE-model picker, and a gear that jumps to the
/// full Image Studio settings dialog. A VIEW over the SAME persisted settings
/// the Studio owns, never a second config surface.
class EngineStrip extends StatelessWidget {
  const EngineStrip({super.key, required this.controller});

  final AvatarCreationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _label(context, 'IMAGE ENGINE'),
              _backendDropdown(context, c),
              _connectionStatus(context, c),
              if (c.backend != ImageGenBackend.remote)
                TextButton(
                  onPressed: c.testingConnection ? null : c.refreshEngine,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Test', style: TextStyle(fontSize: 12)),
                ),
              IconButton(
                tooltip: 'Image Studio settings',
                icon: Icon(
                  Icons.tune,
                  size: 18,
                  color: AppColors.iconSecondary(context),
                ),
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (_) => const ImageGenSettingsDialog(),
                  );
                  // The dialog may have changed backend/URL/model — re-probe.
                  c.refreshEngine();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _label(context, 'CREATE MODEL'),
              ),
              const SizedBox(width: 10),
              Expanded(child: _createModelPicker(context, c)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Bound to the Studio\'s Create-model slot — model memory is split '
            'per task, so a model left in the Edit tab can\'t poison base '
            'generation here.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
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

  Widget _backendDropdown(BuildContext context, AvatarCreationController c) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<ImageGenBackend>(
        value: c.backend,
        dropdownColor: AppColors.surfaceContainerOf(context),
        style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12.5),
        items: ImageGenBackend.values
            .map((b) => DropdownMenuItem(value: b, child: Text(b.label)))
            .toList(),
        onChanged: c.running
            ? null
            : (b) {
                if (b == null) return;
                c.storage.setImageGenBackend(b.key);
                c.refreshEngine();
              },
      ),
    );
  }

  Widget _connectionStatus(BuildContext context, AvatarCreationController c) {
    if (c.backend == ImageGenBackend.remote) {
      final ready = c.engineReady;
      return _statusDot(
        context,
        ok: ready,
        text: ready ? 'API configured' : 'API key or model missing',
      );
    }
    if (c.testingConnection) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.formMasterAccent,
        ),
      );
    }
    if (c.connectionOk == null) {
      return Text(
        'Not tested',
        style: TextStyle(color: AppColors.textTertiary(context), fontSize: 12),
      );
    }
    return _statusDot(
      context,
      ok: c.connectionOk == true,
      text: c.connectionOk == true ? 'Connected' : 'Not reachable',
    );
  }

  Widget _statusDot(BuildContext context, {required bool ok, required String text}) {
    // logReady = the app-wide green "connected" status hue (AppColors const).
    final color = ok ? AppColors.logReady : AppColors.formMasterAccent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  Widget _createModelPicker(BuildContext context, AvatarCreationController c) {
    if (c.loadingModels) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.formMasterAccent,
          ),
        ),
      );
    }
    // Offline fallback: surface the persisted selection even before a fetch.
    final options = c.modelOptions.isNotEmpty
        ? c.modelOptions
        : (c.storage.imageGenModel.isNotEmpty
              ? [(value: c.storage.imageGenModel, label: c.storage.imageGenModel)]
              : const <({String value, String label})>[]);
    if (options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          'Models appear here once the engine is connected.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
          ),
        ),
      );
    }
    return ModelSlotDropdown(
      settings: c.storage.imageGenSettings,
      editSlot: false,
      keyPrefix: 'creator-create-model',
      fontSize: 12,
      decoration: InputDecoration(
        hintText: 'Select',
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      options: options,
    );
  }
}
