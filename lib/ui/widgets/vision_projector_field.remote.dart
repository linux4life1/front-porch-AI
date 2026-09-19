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

part of 'vision_projector_field.dart';

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
