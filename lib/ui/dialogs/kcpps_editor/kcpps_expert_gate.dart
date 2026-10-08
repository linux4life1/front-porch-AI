// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'kcpps_editor_dialog.dart';
import 'kcpps_editor_style.dart';

/// Opens the preset editor, after the "presets are for experts" pop-up
/// unless the user has said not to ask again. True when a preset was saved.
Future<bool> showKcppsPresets(BuildContext context) async {
  final settings = context.read<StorageService>().backendSettings;
  if (!settings.presetGateSkipped) {
    final open = await showDialog<bool>(
      context: context,
      builder: (_) => const KcppsExpertGate(),
    );
    if (open != true) return false;
  }
  if (!context.mounted) return false;
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const KcppsEditorDialog(),
  );
  return saved ?? false;
}

/// "KoboldCpp presets are for experts": the main button keeps it
/// automatic; opening the presets is the second choice.
class KcppsExpertGate extends StatefulWidget {
  const KcppsExpertGate({super.key});

  @override
  State<KcppsExpertGate> createState() => _KcppsExpertGateState();
}

class _KcppsExpertGateState extends State<KcppsExpertGate> {
  bool _skip = false;

  Future<void> _open() async {
    if (_skip) {
      await context.read<StorageService>().backendSettings.setPresetGateSkipped(
        true,
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.cardOf(context),
    insetPadding: const EdgeInsets.all(24),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: AppColors.hairlineOf(context, 0.12)),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'KoboldCpp presets are for experts',
                style: keText(context, size: 19, weight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Here you set by hand how KoboldCpp loads a model: layers on '
              'the graphics card, where the experts go, batch size, chat '
              'memory. Wrong numbers can stop the model from loading.',
              style: keText(
                context,
                size: 14,
                height: 1.5,
                color: AppColors.slateMutedOf(context),
              ),
            ),
            const SizedBox(height: 14),
            Text.rich(
              const TextSpan(
                children: [
                  TextSpan(
                    text:
                        "If you don't know what layers or batch size are, "
                        'keep it automatic.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text:
                        ' The app already picks good settings for your '
                        'computer and tells you, in plain words, if '
                        'something could be faster.',
                  ),
                ],
              ),
              style: keText(context, size: 14, height: 1.5),
            ),
            const SizedBox(height: 14),
            KeCheck(
              value: _skip,
              label: "I know KoboldCpp: don't ask again",
              onChanged: (v) => setState(() => _skip = v),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                KeButton('Open presets', onPressed: _open),
                const SizedBox(width: 10),
                KeButton(
                  'Keep it automatic',
                  kind: KeButtonKind.amber,
                  padding: 18,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
