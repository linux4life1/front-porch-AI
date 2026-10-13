// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The sidebar's Director card: whether the user is in the scene or off
/// stage directing it, the one button that steps them out or back in (the
/// same narrated exit and entrance as `/director`), and, while directing,
/// how long auto-chat waits between replies.
class DirectorPanel extends StatefulWidget {
  const DirectorPanel({
    super.key,
    required this.directing,
    required this.busy,
    required this.delaySeconds,
    required this.onStepOut,
    required this.onStepIn,
    required this.onDelayChanged,
    this.tools,
  });

  final bool directing;

  /// A turn is running, so stepping out or in has to wait.
  final bool busy;
  final double delaySeconds;
  final VoidCallback onStepOut;
  final VoidCallback onStepIn;
  final ValueChanged<double> onDelayChanged;

  /// The director's tools ([DirectorTools]), shown while directing.
  final Widget? tools;

  @override
  State<DirectorPanel> createState() => _DirectorPanelState();
}

class _DirectorPanelState extends State<DirectorPanel> {
  double? _dragDelay; // live value while the slider is held

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final directing = widget.directing;
    final secondary = AppColors.textSecondary(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.movie_creation_outlined,
                size: 16,
                color: directing ? amber : AppColors.iconSecondary(context),
              ),
              const SizedBox(width: 8),
              Text(
                'Director',
                style: TextStyle(color: secondary, fontSize: 13),
              ),
              const Spacer(),
              _StatusPill(directing: directing, amber: amber),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            directing
                ? 'The cast plays on without you. Type a note to steer the '
                      'scene. Bond and trust toward you hold still.'
                : 'Step out to watch the cast play the scene and steer it '
                      'with notes.',
            style: TextStyle(color: secondary, fontSize: 11),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('director-step'),
              onPressed: widget.busy
                  ? null
                  : (directing ? widget.onStepIn : widget.onStepOut),
              icon: Icon(directing ? Icons.login : Icons.logout, size: 16),
              label: Text(directing ? 'Step back in' : 'Step out to direct'),
              style: OutlinedButton.styleFrom(
                foregroundColor: amber,
                side: BorderSide(color: amber.withValues(alpha: 0.5)),
              ),
            ),
          ),
          if (directing) ..._delayRow(context, amber),
          if (directing && widget.tools != null) widget.tools!,
        ],
      ),
    );
  }

  List<Widget> _delayRow(BuildContext context, Color amber) {
    final value = _dragDelay ?? widget.delaySeconds;
    return [
      const SizedBox(height: 8),
      Row(
        children: [
          Text(
            'Auto-chat delay',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 11,
            ),
          ),
          const Spacer(),
          Text(
            '${value.toStringAsFixed(1)}s',
            style: TextStyle(
              color: amber,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        ),
        child: Slider(
          value: value.clamp(0.5, 60.0),
          min: 0.5,
          max: 60.0,
          divisions: 119,
          activeColor: amber,
          inactiveColor: AppColors.borderOf(context).withValues(alpha: 0.3),
          onChanged: (v) => setState(() => _dragDelay = v),
          onChangeEnd: (v) {
            setState(() => _dragDelay = null);
            widget.onDelayChanged(v);
          },
        ),
      ),
    ];
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.directing, required this.amber});

  final bool directing;
  final Color amber;

  @override
  Widget build(BuildContext context) {
    final color = directing ? amber : AppColors.textSecondary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        directing ? 'You\'re directing' : 'You\'re in the scene',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
