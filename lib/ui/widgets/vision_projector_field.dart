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

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/capability/model_capabilities.dart';
import 'package:front_porch_ai/services/capability/vision_support_resolver.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/gguf_vision.dart';

/// Optional "Vision projector (mmproj)" control for a local GGUF model.
///
/// Field state is driven by GGUF detection (via [VisionSupportResolver]):
///  - embedded projector    → "vision built in" + a collapsed "use a custom
///    projector" override for power users;
///  - multimodal, no mmproj  → picker, "add the matching mmproj";
///  - not detected as vision → picker anyway, "if it has a companion mmproj,
///    select it" — the arch heuristic is conservative and misses finetunes /
///    renamed arches, so the user's mmproj is always the authoritative signal.
/// A status pill reflects the resolver's verdict (which trusts an attached
/// mmproj). The picker is only ever hidden when a projector is already baked
/// into the model file.
class VisionProjectorField extends StatefulWidget {
  /// The selected local model file, or null (e.g. a preset owns the model).
  final String? modelPath;
  final StorageService storage;

  /// Called after the mmproj mapping changes so the parent can refresh.
  final VoidCallback? onChanged;

  const VisionProjectorField({
    super.key,
    required this.modelPath,
    required this.storage,
    this.onChanged,
  });

  @override
  State<VisionProjectorField> createState() => _VisionProjectorFieldState();
}

class _VisionProjectorFieldState extends State<VisionProjectorField> {
  GgufVisionInfo? _info;
  bool _loading = false;
  bool _showCustomOverride = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(VisionProjectorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelPath != widget.modelPath) {
      _showCustomOverride = false;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final path = widget.modelPath;
    if (path == null) {
      setState(() {
        _info = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final info = await VisionSupportResolver.instance.resolveLocalGgufInfo(
      path,
    );
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  String? get _mmprojPath {
    final path = widget.modelPath;
    if (path == null) return null;
    final v = widget.storage.modelMmprojMap[path];
    return (v != null && v.isNotEmpty) ? v : null;
  }

  bool get _mmprojExists {
    final m = _mmprojPath;
    return m != null && File(m).existsSync();
  }

  Future<void> _pickMmproj() async {
    final path = widget.modelPath;
    if (path == null) return;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gguf'],
      dialogTitle: 'Select vision projector (mmproj .gguf)',
    );
    if (result == null || result.files.single.path == null) return;
    await widget.storage.setModelMmproj(path, result.files.single.path);
    if (!mounted) return;
    setState(() {});
    widget.onChanged?.call();
  }

  Future<void> _clearMmproj() async {
    final path = widget.modelPath;
    if (path == null) return;
    await widget.storage.setModelMmproj(path, null);
    if (!mounted) return;
    setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to configure when no concrete model file is selected.
    if (widget.modelPath == null) return const SizedBox.shrink();

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.iconSecondary(context),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Checking vision support…',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary(context),
              ),
            ),
          ],
        ),
      );
    }

    final info = _info;
    final support = VisionSupport.fromGguf(
      info,
      mmprojConfigured: _mmprojExists,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 16,
                color: AppColors.iconSecondary(context),
              ),
              const SizedBox(width: 8),
              Text(
                'Vision projector (mmproj)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const Spacer(),
              _statusPill(context, support),
            ],
          ),
          const SizedBox(height: 8),
          _body(context, info),
        ],
      ),
    );
  }

  Widget _statusPill(BuildContext context, VisionSupport support) =>
      visionStatusPill(context, support);

  /// The state-specific body: greyed built-in, enabled picker, or greyed
  /// text-only note.
  Widget _body(BuildContext context, GgufVisionInfo? info) {
    // Couldn't parse the file — allow a manual override just in case.
    if (info == null) {
      return _pickerRow(
        context,
        hint:
            'Could not read this model. Add an mmproj if it is a vision model.',
      );
    }

    if (info.hasEmbeddedProjector) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note(
            context,
            'Vision is built into this model — no projector needed.',
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () =>
                setState(() => _showCustomOverride = !_showCustomOverride),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _showCustomOverride ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 4),
                Text(
                  'Use a custom projector',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
          if (_showCustomOverride) ...[
            const SizedBox(height: 6),
            _pickerRow(
              context,
              hint: 'Override the built-in projector with your own mmproj.',
            ),
          ],
        ],
      );
    }

    if (info.needsExternalProjector) {
      return _pickerRow(
        context,
        hint: 'Multimodal model — add the matching mmproj to enable vision.',
      );
    }

    // Not detected as a vision model. Detection is deliberately conservative
    // (an arch allowlist), so it misses finetunes, renamed arches, and models
    // whose vision config lives only in the mmproj. Still offer the picker: if
    // the user has this model's companion mmproj, attaching it is what enables
    // vision (KoboldCpp loads it via --mmproj) and flips the pill to supported.
    return _pickerRow(
      context,
      hint:
          'No vision detected in this model. If it has a companion mmproj '
          '(vision) file, select it to enable vision.',
    );
  }

  Widget _pickerRow(BuildContext context, {required String hint}) {
    final mmproj = _mmprojPath;
    final exists = _mmprojExists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hint,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary(context),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                mmproj == null
                    ? 'No projector selected'
                    : (exists
                          ? p.basename(mmproj)
                          : '${p.basename(mmproj)} (missing)'),
                style: TextStyle(
                  fontSize: 12,
                  color: mmproj == null
                      ? AppColors.textTertiary(context)
                      : (exists
                            ? AppColors.textPrimary(context)
                            : AppColors.resolve(
                                context,
                                Colors.redAccent,
                                Colors.red.shade700,
                              )),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (mmproj != null)
              IconButton(
                onPressed: _clearMmproj,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove projector',
                color: AppColors.iconSecondary(context),
                visualDensity: VisualDensity.compact,
              ),
            OutlinedButton.icon(
              onPressed: _pickMmproj,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Browse'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary(context),
                side: BorderSide(color: AppColors.borderOf(context)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _note(BuildContext context, String text, {bool muted = false}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: muted
            ? AppColors.textTertiary(context)
            : AppColors.textSecondary(context),
      ),
    );
  }
}

/// Shared "Vision: supported / none / unknown" pill, driven by a resolver
/// verdict. "Unknown" (server unreachable, model still loading, inconclusive
/// error) is rendered distinctly so a failed CHECK never reads as a
/// definitive "this model can't see".
Widget visionStatusPill(BuildContext context, VisionSupport support) {
  final green = AppColors.resolve(
    context,
    Colors.greenAccent,
    Colors.green.shade700,
  );
  final unknown = support.source == VisionSource.unknown;
  final color = support.supported ? green : AppColors.textTertiary(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      support.supported
          ? 'Vision: supported'
          : (unknown ? 'Vision: could not check' : 'Vision: none'),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
    ),
  );
}

/// Vision status for a remote (OpenAI-compatible) model, reading the same
/// [VisionSupportResolver]. OpenRouter / Nano-GPT resolve automatically from
/// free `/models` metadata; generic backends expose a manual "Check vision"
/// button so the runtime image probe is never fired (and can never cost a
/// token) without the user asking for it.
class RemoteVisionPill extends StatefulWidget {
  final String apiUrl;
  final String apiKey;
  final String modelName;

  const RemoteVisionPill({
    super.key,
    required this.apiUrl,
    required this.apiKey,
    required this.modelName,
  });

  @override
  State<RemoteVisionPill> createState() => _RemoteVisionPillState();
}

class _RemoteVisionPillState extends State<RemoteVisionPill> {
  VisionSupport? _support;
  bool _loading = false;

  // Metadata providers resolve for free (no probe request), so auto-resolving
  // on init is safe only for them — the shared host check keeps this UI, the
  // resolver, and the tool-calling short-circuit classifying identically.
  bool get _isMetadataProvider =>
      isCapabilityMetadataProviderUrl(widget.apiUrl);

  @override
  void initState() {
    super.initState();
    if (widget.modelName.isNotEmpty && _isMetadataProvider) _resolve();
  }

  @override
  void didUpdateWidget(RemoteVisionPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelName != widget.modelName ||
        oldWidget.apiUrl != widget.apiUrl) {
      _support = null;
      if (widget.modelName.isNotEmpty && _isMetadataProvider) _resolve();
    }
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
    });
    final support = await VisionSupportResolver.instance.resolveRemote(
      apiUrl: widget.apiUrl,
      apiKey: widget.apiKey,
      modelName: widget.modelName,
    );
    if (!mounted) return;
    setState(() {
      _support = support;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.modelName.isEmpty) return const SizedBox.shrink();

    if (_loading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.iconSecondary(context),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Checking vision…',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      );
    }

    final support = _support;
    if (support != null && support.source != VisionSource.unknown) {
      return visionStatusPill(context, support);
    }

    // Not yet requested (generic backend), or the last check was
    // inconclusive (server unreachable / model still loading) → offer a
    // manual check. Unknown verdicts are never cached, so retrying re-probes.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (support != null) ...[
          visionStatusPill(context, support),
          const SizedBox(width: 8),
        ],
        TextButton.icon(
          onPressed: _resolve,
          icon: Icon(
            Icons.visibility_outlined,
            size: 16,
            color: AppColors.iconSecondary(context),
          ),
          label: Text(
            support == null ? 'Check vision support' : 'Retry check',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
            ),
          ),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
        ),
      ],
    );
  }
}
