// Copyright header standard
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../widgets/eval_pill.dart';

class RealismProcessingOverlay extends StatefulWidget {
  final ChatService chatService;
  final bool isGreeting;

  const RealismProcessingOverlay({
    super.key,
    required this.chatService,
    required this.isGreeting,
  });

  @override
  State<RealismProcessingOverlay> createState() =>
      RealismProcessingOverlayState();
}

class RealismProcessingOverlayState extends State<RealismProcessingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  late final AnimationController _fadeController;
  late final Animation<double> _pulse;
  late final Animation<double> _rotate;
  late final Animation<double> _fade;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
    _rotate = CurvedAnimation(parent: _rotateController, curve: Curves.linear);
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _fadeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGreeting = widget.isGreeting;
    // Warm porch in both modes: one amber accent on the theme's surfaces.
    final accentColor = AppColors.porchAmberOf(context);
    final isVerifying = widget.chatService.isVerifyingRealism;
    final vPass = widget.chatService.verificationPass;
    final vMax = widget.chatService.verificationMaxPasses;
    final title = isGreeting
        ? 'Reading the room...'
        : isVerifying
        ? '🕵️ Verifying Realism output${(vMax > 0) ? ' (pass $vPass/$vMax)' : ''}'
        : 'Realism Engine';
    final subtitle = isGreeting
        ? 'Capturing emotional baseline from opening message'
        : isVerifying
        ? 'Director thread checking deltas + latent context; applying corrections or reprocessing as needed'
        : 'Evaluating relationship, mood & scene state';

    final pills = isGreeting
        ? <EvalPill>[
            EvalPill(label: 'Emotion', icon: Icons.mood, color: accentColor),
            EvalPill(
              label: 'Bond',
              icon: Icons.favorite_border,
              color: accentColor,
            ),
            EvalPill(
              label: 'Trust',
              icon: Icons.handshake_outlined,
              color: accentColor,
            ),
          ]
        : <EvalPill>[
            if (widget.chatService.isCheckingCompletion)
              EvalPill(
                label: 'Objective',
                icon: Icons.flag,
                color: accentColor,
              ),
            EvalPill(
              label: 'Relationship',
              icon: Icons.favorite_border,
              color: accentColor,
            ),
            EvalPill(label: 'Emotion', icon: Icons.mood, color: accentColor),
            EvalPill(
              label: 'Scene',
              icon: Icons.wb_twilight,
              color: accentColor,
            ),
            EvalPill(
              label: 'Trust',
              icon: Icons.handshake_outlined,
              color: accentColor,
            ),
          ];

    return Positioned.fill(
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          type: MaterialType.transparency,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              // A dark dim in both themes so the panel keeps the focus.
              color: Colors.black.withValues(alpha: 0.55),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 680,
                    maxHeight: 580,
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: AppColors.isLight(context) ? 0.18 : 0.6,
                          ),
                          blurRadius: 60,
                          offset: const Offset(0, 24),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Header ───────────────────────────────────────────
                        Container(
                          padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: accentColor.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Animated orb with spinning ring
                              AnimatedBuilder(
                                animation: _pulse,
                                builder: (_, _) => Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        accentColor.withValues(
                                          alpha: 0.3 + 0.15 * _pulse.value,
                                        ),
                                        accentColor.withValues(alpha: 0.04),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accentColor.withValues(
                                          alpha: 0.12 + 0.1 * _pulse.value,
                                        ),
                                        blurRadius: 20 + 12 * _pulse.value,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      RotationTransition(
                                        turns: _rotate,
                                        child: Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: accentColor.withValues(
                                                alpha: 0.3,
                                              ),
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        isGreeting
                                            ? Icons.auto_awesome
                                            : Icons.psychology,
                                        color: accentColor,
                                        size: 22,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary(context),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitle,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textSecondary(context),
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: accentColor.withValues(alpha: 0.6),
                                  strokeWidth: 1.8,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── Eval Pills ────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 18, 28, 4),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: pills
                                .map(
                                  (p) => AnimatedEvalPill(
                                    pill: p,
                                    pulseAnimation: _pulse,
                                  ),
                                )
                                .toList(),
                          ),
                        ),

                        // ── Content area ──────────────────────────────────────
                        if (!isGreeting &&
                            widget
                                .chatService
                                .realismEvalStreamTextClean
                                .isNotEmpty) ...[
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                14,
                                20,
                                20,
                              ),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  16,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.sunkenSurfaceOf(context),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: accentColor.withValues(alpha: 0.15),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        AnimatedBuilder(
                                          animation: _pulse,
                                          builder: (_, _) => Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: accentColor.withValues(
                                                alpha: 0.5 + 0.5 * _pulse.value,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'LIVE EVAL STREAM',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: accentColor.withValues(
                                              alpha: 0.85,
                                            ),
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Expanded(
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: Scrollbar(
                                          controller: _scrollController,
                                          thumbVisibility: true,
                                          child: SingleChildScrollView(
                                            controller: _scrollController,
                                            reverse: true,
                                            child: Text(
                                              widget
                                                  .chatService
                                                  .realismEvalStreamTextClean,
                                              style: TextStyle(
                                                color: AppColors.textSecondary(
                                                  context,
                                                ),
                                                fontSize: 11.5,
                                                fontFamily: 'monospace',
                                                height: 1.65,
                                                letterSpacing: 0.15,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (widget.chatService.isEvaluatingRealism ||
                              widget.chatService.isProcessingGreeting) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Column(
                                children: [
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton(
                                      onPressed:
                                          widget
                                              .chatService
                                              .isCancellingRealismEval
                                          ? null
                                          : () => widget.chatService
                                                .cancelRealismEval(),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.redAccent,
                                      ),
                                      child: const Text(
                                        'Stop this reply',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ] else ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                            child: AnimatedBuilder(
                              animation: _pulse,
                              builder: (_, _) => Text(
                                isGreeting
                                    ? 'Analyzing opening message to calibrate\nthe character\'s emotional state & relationships...'
                                    : 'Initializing evaluator...',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textPrimary(context)
                                      .withValues(
                                        alpha: 0.35 + 0.15 * _pulse.value,
                                      ),
                                  height: 1.65,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
