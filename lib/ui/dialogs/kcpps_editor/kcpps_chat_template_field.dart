// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'kcpps_editor.dart';

class KcppsChatTemplateField extends StatefulWidget {
  const KcppsChatTemplateField({
    super.key,
    required this.engineDir,
    required this.path,
    required this.onChanged,
    this.pickFile,
  });
  final String engineDir;
  final String path;
  final ValueChanged<String> onChanged;
  final Future<String?> Function()? pickFile;

  @override
  State<KcppsChatTemplateField> createState() => _ChatTemplateFieldState();
}

class _ChatTemplateFieldState extends State<KcppsChatTemplateField> {
  bool _busy = false;
  String? _error;

  Future<void> _choose() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String? selected;
      if (widget.pickFile != null) {
        selected = await widget.pickFile!();
      } else {
        final result = await GuardedPicker.pickFiles(
          context,
          category: PickerPrefs.catImport,
          type: FileType.custom,
          allowedExtensions: ['jinja'],
        );
        selected = result?.files.single.path;
      }
      if (selected == null) return;
      final source = File(selected);
      if (await source.length() > kChatTemplateMaxBytes) {
        throw const FormatException('Choose a .jinja file up to 64 KiB.');
      }
      final imported = await copyKoboldChatTemplate(
        engineDir: widget.engineDir,
        name: p.basename(selected),
        content: await source.readAsString(),
      );
      if (mounted) widget.onChanged(imported);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => KeSection(
    title: 'Chat template',
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          KeButton(
            widget.path.isEmpty
                ? 'Choose .jinja file…'
                : p.basename(widget.path),
            onPressed: _busy ? null : _choose,
          ),
          if (widget.path.isNotEmpty)
            KeButton(
              'Use embedded template',
              onPressed: _busy ? null : () => widget.onChanged(''),
            ),
        ],
      ),
      if (widget.path.isNotEmpty)
        SelectableText(
          widget.path,
          style: keText(
            context,
            size: 12,
            color: AppColors.slateMutedOf(context),
          ),
        ),
      Text(
        'An optional .jinja file overrides the template embedded in the GGUF. '
        'Save the preset, then stop and restart KoboldCpp to apply a template change.',
        style: keText(
          context,
          size: 12,
          color: AppColors.slateFaintOf(context),
        ),
      ),
      if (_busy) const Text('Importing template…'),
      if (_error != null)
        Text(_error!, style: TextStyle(color: AppColors.logError)),
    ],
  );
}
