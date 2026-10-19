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

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

import 'prompt_progress_bar.dart';

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
    // 250ms so the estimate fill and the time left move between the
    // backend's per-batch console lines (tiny widget, cheap rebuild).
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
        ChatColors.preparingOf(context),
        Icons.build_rounded,
        false,
      ),
      GenerationPhase.prefilling => _prefillLabel(cs),
      GenerationPhase.thinking => _thinkingLabel(cs),
      GenerationPhase.buffering => (
        'Buffering tokens...',
        ChatColors.bufferingOf(context),
        Icons.hourglass_top_rounded,
        true,
      ),
      GenerationPhase.generating => (
        'Generating response...',
        ChatColors.generatingOf(context),
        Icons.bolt_rounded,
        true,
      ),
      GenerationPhase.impersonating => (
        'Writing your reply…',
        AppColors.porchAmberOf(context),
        Icons.auto_fix_high,
        false,
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
                    color: ChatColors.speedOf(context),
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
            ChatColors.generatingOf(context),
            cs.generationProgress,
          )!,
        ),
      );
    }
    if (phase == GenerationPhase.prefilling) {
      // Determinate whenever the active backend gave us real numbers: solid
      // for what it confirmed, lighter for the estimate (see LiveGenProgress
      // for where the speed comes from and how far the guess may run).
      final live = cs.activeLiveProgress;
      final estimated = live?.estimatedPromptFraction(
        tokensPerSecond: _prefillSpeed(cs),
        requestElapsed: _ownRequestElapsed(cs),
      );
      if (live != null && estimated != null) {
        return PromptProgressBar(
          confirmed: live.confirmedFraction() ?? 0,
          estimated: estimated,
          passEpoch: live.passEpoch,
          color: accentColor,
        );
      }
    }
    return LinearProgressIndicator(
      minHeight: 4,
      backgroundColor: AppColors.hairlineOf(context, 0.08),
      valueColor: AlwaysStoppedAnimation<Color>(
        accentColor.withValues(alpha: 0.7),
      ),
    );
  }

  (String, Color, IconData, bool) _prefillLabel(ChatService cs) {
    final elapsed = cs.prefillElapsedSeconds;
    final elapsedStr = elapsed >= 1 ? ' (${elapsed.toInt()}s)' : '';
    final color = ChatColors.prefillingOf(context);

    // The single-slot local backend serializes requests, so our reply can be
    // stuck behind a background pass — app-side knowledge, safely
    // attributable. A backend-reported queue (oMLX waiting[]) is NOT
    // attributable (it may be someone waiting on us), so it is stated as a
    // neutral fact instead (review finding: attributing it was invertible).
    final live = cs.activeLiveProgress;
    // The reply may also wait for what has the engine (the speed test).
    final String? busyWith = cs.isSummaryGenerating
        ? 'journal pass'
        : (cs.isGrowthPassRunning ? 'growth pass' : live?.heldBy);
    final queueNote = (live != null && live.isFresh && live.waitingCount > 0)
        ? ' — ${live.waitingCount} request${live.waitingCount == 1 ? '' : 's'} queued'
        : '';

    if (live != null && live.isFresh && live.promptTotal > 0) {
      // The words carry only what the backend confirmed ("8,192 / 22,124");
      // the estimate lives in the bar's lighter fill and the "~time left",
      // so a guess never reads as a count (Discord report: the label once
      // said 21,303 while the console had finished 8,192).
      final confirmed = live.confirmedFraction() ?? 0;
      final rawDone = confirmed >= 1.0;
      final pct = (confirmed * 100).toInt();
      final counts =
          '${_fmtExact(live.promptConfirmed)} / ${_fmtExact(live.promptTotal)} tokens';
      final left = busyWith == null
          ? _fmtLeft(
              live.estimatedPromptSecondsLeft(
                tokensPerSecond: _prefillSpeed(cs),
                requestElapsed: _ownRequestElapsed(cs),
              ),
            )
          : '';
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
          'Reading prompt — $counts ($pct%)$left$elapsedStr$queueNote',
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

    // No live console data yet. Kobold may show its tokenizer estimate
    // until the console ticker arrives. oMLX and remote hosts must not:
    // that estimate is chars/4, and lastPerfData can be a leftover Kobold
    // speed. Elapsed time is the honest label until real progress exists.
    if (!cs.prefillMetricsAreMeasured) {
      final label = busyWith != null
          ? 'Waiting — $busyWith is using the model$elapsedStr'
          : 'Processing prompt$elapsedStr$queueNote';
      return (label, color, Icons.memory_rounded, false);
    }
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

  /// '' or " · ~3 min left" (rounded so it does not flicker every tick).
  String _fmtLeft(double? seconds) {
    if (seconds == null || seconds.isNaN || seconds.isInfinite) return '';
    if (seconds < 60) {
      return ' · ~${((seconds / 5).ceil() * 5).clamp(5, 60)}s left';
    }
    return ' · ~${(seconds / 60).ceil()} min left';
  }

  /// How long our own reply has been waiting on the prompt, so the estimate
  /// can use this request's average speed. Null while a background pass has
  /// the engine: the live counts are then that pass's, not ours.
  Duration? _ownRequestElapsed(ChatService cs) {
    if (cs.isSummaryGenerating || cs.isGrowthPassRunning) return null;
    if (cs.activeLiveProgress?.heldBy != null) return null;
    final seconds = cs.prefillElapsedSeconds;
    if (seconds <= 0) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// A previous request's prefill speed (t/s) from the perf poll: the last
  /// resort for the estimate, used only before this request proves its own.
  double? _prefillSpeed(ChatService cs) {
    if (!cs.prefillMetricsAreMeasured) return null;
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
      ChatColors.thinkingOf(context),
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
