// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'kcpps_editor_controller.dart';
import 'kcpps_editor_style.dart';

/// "Your presets": every preset, the one chat uses marked, and the ways to
/// start a new one.
class KcppsPresetList extends StatelessWidget {
  const KcppsPresetList({
    super.key,
    required this.c,
    required this.onSelect,
    required this.onNew,
    required this.onOpen,
  });

  final KcppsEditorController c;
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Container(
    width: 300,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.insetPanelOf(context),
      border: Border(
        right: BorderSide(color: AppColors.hairlineOf(context, 0.08)),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'YOUR PRESETS',
            style: keText(
              context,
              size: 13,
              weight: FontWeight.w700,
              spacing: 0.78,
              color: AppColors.slateFaintOf(context),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              if (c.path == null) ...[
                _item(
                  context,
                  name: c.draft.name,
                  line: 'Not saved yet',
                  on: true,
                ),
                const SizedBox(height: 12),
              ],
              // The preset chat uses comes first.
              for (final preset in [
                ...c.presets.where((e) => c.isChatPreset(e.path)),
                ...c.presets.where((e) => !c.isChatPreset(e.path)),
              ]) ...[
                _item(
                  context,
                  name: preset.name,
                  line: kcppsShortLine(preset.read),
                  on: c.path != null && p.equals(c.path!, preset.path),
                  inUse: c.isChatPreset(preset.path),
                  onTap: () => onSelect(preset.path),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        KeButton(
          'New from my settings',
          kind: KeButtonKind.amberOutline,
          expand: true,
          onPressed: onNew,
        ),
        const SizedBox(height: 12),
        KeButton('Open a .kcpps file…', expand: true, onPressed: onOpen),
      ],
    ),
  );

  Widget _item(
    BuildContext context, {
    required String name,
    required String line,
    required bool on,
    bool inUse = false,
    VoidCallback? onTap,
  }) {
    final amber = AppColors.porchAmberOf(context);
    return Semantics(
      selected: on,
      button: true,
      child: Material(
        color: on ? amber.withValues(alpha: 0.10) : AppColors.cardOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: on
                ? amber.withValues(alpha: 0.55)
                : AppColors.hairlineOf(context, 0.10),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: keText(
                          context,
                          size: 15,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (inUse)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.porchAmber,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'IN USE',
                          style: keText(
                            context,
                            size: 11,
                            weight: FontWeight.w700,
                            color: AppColors.onPorchAmber,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  line,
                  style: keText(
                    context,
                    size: 12,
                    color: AppColors.slateMutedOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
