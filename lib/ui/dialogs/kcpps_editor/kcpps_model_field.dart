// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'kcpps_editor_controller.dart';
import 'kcpps_editor_style.dart';

/// The model a preset loads, with what the app knows about it.
class KcppsModelField extends StatelessWidget {
  const KcppsModelField({super.key, required this.c});

  final KcppsEditorController c;

  String _label(String path) {
    final size = c.modelSizes[path];
    return size == null
        ? p.basename(path)
        : '${p.basename(path)} (${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB)';
  }

  @override
  Widget build(BuildContext context) {
    final current = c.draft.modelPath;
    final models = {...c.models, if (current.isNotEmpty) current}.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const KeLabel('Model'),
        const SizedBox(height: 6),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.sunkenSurfaceOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.hairlineOf(context, 0.14)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const ValueKey('kcpps-model'),
              value: current.isEmpty ? null : current,
              isExpanded: true,
              hint: Text(
                'Choose a model',
                style: keText(
                  context,
                  size: 15,
                  color: AppColors.slateFaintOf(context),
                ),
              ),
              dropdownColor: AppColors.sunkenSurfaceOf(context),
              iconEnabledColor: AppColors.slateMutedOf(context),
              style: keText(context, size: 15),
              items: [
                for (final m in models)
                  DropdownMenuItem(
                    value: m,
                    child: Text(_label(m), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (m) {
                if (m != null && m != current) c.setModel(m);
              },
            ),
          ),
        ),
        if (c.modelFacts.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final f in c.modelFacts) KeChip(f)],
          ),
        ],
      ],
    );
  }
}
