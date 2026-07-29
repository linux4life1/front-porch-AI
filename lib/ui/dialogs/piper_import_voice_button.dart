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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/voice_manager.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// "Add custom voice" for the Piper Voice Model Browser: picks a raw Piper
/// `.onnx` (its sibling `.onnx.json` must sit next to it — the standard
/// pair every Piper voice ships as), converts it in-app to the sherpa
/// bundle layout via [VoiceManager.importCustomPiperVoice], and reports the
/// result. Lives in its own file so the browser dialog stays under the
/// 500-line cap.
class PiperImportVoiceButton extends StatefulWidget {
  /// Called with the new voice key after a successful install, so the
  /// browser can mark it installed without a full reload.
  final void Function(String voiceKey) onImported;

  const PiperImportVoiceButton({super.key, required this.onImported});

  @override
  State<PiperImportVoiceButton> createState() => _PiperImportVoiceButtonState();
}

class _PiperImportVoiceButtonState extends State<PiperImportVoiceButton> {
  bool _importing = false;

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['onnx'],
      dialogTitle: 'Pick a Piper voice model (.onnx)',
    );
    final path = result?.files.firstOrNull?.path;
    if (path == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final vm = Provider.of<VoiceManager>(context, listen: false);
      final key = await vm.importCustomPiperVoice(path);
      if (!mounted) return;
      widget.onImported(key);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Custom voice "$key" installed — ready to use.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FormatException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.negativeAccentOf(context),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return OutlinedButton.icon(
      onPressed: _importing ? null : _import,
      icon: _importing
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: amber),
            )
          : const Icon(Icons.add, size: 18),
      label: Text(_importing ? 'Importing…' : 'Add custom voice'),
      style: OutlinedButton.styleFrom(
        foregroundColor: amber,
        side: BorderSide(color: amber.withValues(alpha: 0.6)),
      ),
    );
  }
}
