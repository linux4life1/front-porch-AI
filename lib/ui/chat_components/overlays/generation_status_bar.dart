// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// ... full standard header ...
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Rich, phase-aware generation status bar. (extracted)
class GenerationStatusBar extends StatefulWidget {
  final ChatService chatService;
  const GenerationStatusBar({super.key, required this.chatService});

  @override
  State<GenerationStatusBar> createState() => _GenerationStatusBarState();
}

class _GenerationStatusBarState extends State<GenerationStatusBar> {
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    // 250ms so the interpolated prompt-token counter visibly ticks between
    // the backend's per-batch console lines (tiny widget, cheap rebuild).
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.chatService;
    final phase = cs.generationPhase;

    final (
      String label,
      Color accentColor,
      IconData icon,
      bool showMetrics,
    ) = switch (phase) {
      GenerationPhase.preparing => (
        'Assembling prompt...',
        AppColors.resolve(
          context,
          const Color(0xFFF59E0B),
          const Color(0xFFB45309),
        ),
        Icons.build_rounded,
        false,
      ),
      GenerationPhase.prefilling => _prefillLabel(cs),
      GenerationPhase.thinking => _thinkingLabel(cs),
      GenerationPhase.buffering => (
        'Buffering tokens...',
        AppColors.resolve(
          context,
          const Color(0xFF3B82F6),
          const Color(0xFF1D4ED8),
        ),
        Icons.hourglass_top_rounded,
        true,
      ),
      GenerationPhase.generating => (
        'Generating response...',
        AppColors.resolve(
          context,
          const Color(0xFF10B981),
          const Color(0xFF059669),
        ),
        Icons.bolt_rounded,
        true,
      ),
      GenerationPhase.idle => (
        'Idle',
        AppColors.textTertiary(context),
        Icons.check_rounded,
        false,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        border: Border(
          top: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child:
                    phase == GenerationPhase.prefilling ||
                        phase == GenerationPhase.preparing
                    ? PulsingIcon(icon: icon, color: accentColor)
                    : Icon(icon, size: 16, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: accentColor.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showMetrics) ...[
                Text(
                  '${cs.tokensPerSecond.toStringAsFixed(1)} t/s',
                  style: TextStyle(
                    color: AppColors.resolve(
                      context,
                      Colors.amberAccent,
                      const Color(0xFFB45309),
                    ),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${cs.tokensGenerated} / ${cs.maxTokens}',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(cs.generationProgress * 100).toInt()}%',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: _buildProgressBar(cs, phase, accentColor),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(
    ChatService cs,
    GenerationPhase phase,
    Color accentColor,
  ) {
    if (phase == GenerationPhase.generating ||
        phase == GenerationPhase.buffering) {
      return LinearProgressIndicator(
        value: cs.generationProgress,
        minHeight: 4,
        backgroundColor: AppColors.borderOf(context).withValues(alpha: 0.08),
        valueColor: AlwaysStoppedAnimation<Color>(
          Color.lerp(
            accentColor,
            AppColors.resolve(
              context,
              AppColors.resolve(
                context,
                const Color(0xFF10B981),
                const Color(0xFF059669),
              ),
              const Color(0xFF059669),
            ),
            cs.generationProgress,
          )!,
        ),
      );
    }
    if (phase == GenerationPhase.prefilling) {
      // Determinate whenever the active backend gave us real numbers — the
      // prompt pass stops being a black box. Interpolated between per-batch
      // updates (see _prefillLabel), monotonic per pass (the ratchet in
      // LiveGenProgress), and tweened here so the 250ms rebuild ticks glide
      // instead of stepping.
      final fraction = cs.activeLiveProgress?.estimatedPromptFraction(
        tokensPerSecond: _prefillSpeed(cs),
      );
      if (fraction != null) {
        return TweenAnimationBuilder<double>(
          // Keyed on the pass epoch: an honest pass restart rebuilds the bar
          // AT the new fraction instead of sweeping backwards through the
          // old one — backwards motion is the exact bug this bar had.
          key: ValueKey(cs.activeLiveProgress?.passEpoch ?? 0),
          tween: Tween<double>(end: fraction),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          builder: (context, animated, _) => LinearProgressIndicator(
            value: animated.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: AppColors.borderOf(
              context,
            ).withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(accentColor),
          ),
        );
      }
    }
    return LinearProgressIndicator(
      minHeight: 4,
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      valueColor: AlwaysStoppedAnimation<Color>(
        accentColor.withValues(alpha: 0.7),
      ),
    );
  }

  (String, Color, IconData, bool) _prefillLabel(ChatService cs) {
    final elapsed = cs.prefillElapsedSeconds;
    final elapsedStr = elapsed >= 1 ? ' (${elapsed.toInt()}s)' : '';
    const color = Color(0xFFF97316);

    // The single-slot local backend serializes requests, so our reply can be
    // stuck behind a background pass — app-side knowledge, safely
    // attributable. A backend-reported queue (oMLX waiting[]) is NOT
    // attributable (it may be someone waiting on us), so it is stated as a
    // neutral fact instead (review finding: attributing it was invertible).
    final live = cs.activeLiveProgress;
    final String? busyWith = cs.isSummaryGenerating
        ? 'journal pass'
        : (cs.isGrowthPassRunning ? 'growth pass' : null);
    final queueNote = (live != null && live.isFresh && live.waitingCount > 0)
        ? ' — ${live.waitingCount} request${live.waitingCount == 1 ? '' : 's'} queued'
        : '';

    if (live != null && live.isFresh && live.promptTotal > 0) {
      // Console lines arrive once per BATCH (with --batchsize 8192 a ~10K
      // prompt prints only two), so the displayed fraction interpolates
      // between real anchors using the backend's measured prefill speed —
      // otherwise the bar jumps 0% → 100% and just sits there (maintainer
      // report). Raw 100% means the console really said so.
      final rawDone = (live.promptFraction() ?? 0) >= 1.0;
      final estFraction =
          live.estimatedPromptFraction(tokensPerSecond: _prefillSpeed(cs)) ??
          0;
      final pct = (estFraction * 100).toInt();
      final estTokens = rawDone
          ? live.promptTotal
          : (live.promptTotal * estFraction).round();
      // Exact live-ticking counts ("8,347 / 9,912") — the user asked to watch
      // the tokens count up, not just a percent.
      final counts =
          '${_fmtExact(estTokens)} / ${_fmtExact(live.promptTotal)} tokens';
      if (busyWith != null) {
        // Whatever Kobold is chewing on right now is the BACKGROUND call;
        // our reply is queued behind it.
        final stage = live.genTotal > 0
            ? 'writing (${live.genCurrent} tokens)'
            : (rawDone ? 'finishing up' : 'reading $counts ($pct%)');
        return (
          'Waiting — $busyWith is using the model: $stage$elapsedStr',
          color,
          Icons.hourglass_top_rounded,
          false,
        );
      }
      if (!rawDone) {
        return (
          'Reading prompt — $counts ($pct%)$elapsedStr$queueNote',
          color,
          Icons.memory_rounded,
          false,
        );
      }
      // Prompt fully read. If decode is running but no token has reached us
      // yet, that decode IS our own reply warming up (buffering / suppressed
      // thinking / first-token latency) — only a busyWith flag above marks
      // the slot as genuinely someone else's.
      return (
        live.genTotal > 0
            ? 'Starting the reply — ${live.genCurrent} tokens written$elapsedStr$queueNote'
            : 'Prompt read — starting the reply…$elapsedStr$queueNote',
        color,
        Icons.bolt_rounded,
        false,
      );
    }

    // No live console data (remote backend, or nothing printed yet): keep the
    // estimate-based label.
    final promptTokens = cs.prefillPromptTokens;
    String tokenStr = '';
    if (promptTokens > 0) {
      tokenStr = '~${_fmtTokens(promptTokens)} tokens';
    }
    final perf = cs.lastPerfData;
    String speedStr = '';
    if (perf != null) {
      final idle = perf['idle'];
      if (idle == 0) {
        final speed = perf['last_process_speed'];
        if (speed != null && speed is num && speed > 0) {
          speedStr = '~${speed.toStringAsFixed(0)} t/s';
        }
      }
    }
    final parts = <String>[
      if (tokenStr.isNotEmpty) tokenStr,
      if (speedStr.isNotEmpty) speedStr,
    ];
    final detail = parts.isNotEmpty ? ' — ${parts.join(', ')}' : '';
    final label = busyWith != null
        ? 'Waiting — $busyWith is using the model$elapsedStr'
        : 'Processing prompt$elapsedStr$detail';
    return (label, color, Icons.memory_rounded, false);
  }

  String _fmtTokens(int n) {
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(0)}K';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  /// Exact count with thousands separators (8,347) for the live ticker.
  String _fmtExact(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  /// The backend's measured prefill speed (t/s) from the perf poll — the
  /// anchor for interpolating progress between per-batch console lines.
  double? _prefillSpeed(ChatService cs) {
    final speed = cs.lastPerfData?['last_process_speed'];
    return (speed is num && speed > 0) ? speed.toDouble() : null;
  }

  (String, Color, IconData, bool) _thinkingLabel(ChatService cs) {
    final tokens = cs.tokensGenerated;
    final tps = cs.tokensPerSecond;
    String detail = '';
    if (tokens > 0 && tps > 0) {
      detail = ' — ${tps.toStringAsFixed(1)} t/s, $tokens tokens';
    } else if (tokens > 0) {
      detail = ' — $tokens tokens';
    }
    return (
      'Model is thinking...$detail',
      const Color(0xFFA855F7),
      Icons.psychology_rounded,
      false,
    );
  }
}

/// Pulsing icon (extracted).
class PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  const PulsingIcon({super.key, required this.icon, required this.color});

  @override
  State<PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.4 + (_controller.value * 0.6),
          child: Icon(widget.icon, size: 16, color: widget.color),
        );
      },
    );
  }
}
