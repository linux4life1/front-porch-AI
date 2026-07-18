import 'dart:math';

import 'package:flutter/material.dart';

class EmojiBurst extends StatefulWidget {
  final String? emoji;
  final bool enabled;
  final bool generating;
  final double size;
  final Widget child;

  const EmojiBurst({
    super.key,
    required this.emoji,
    required this.enabled,
    required this.generating,
    required this.size,
    required this.child,
  });

  @override
  State<EmojiBurst> createState() => _EmojiBurstState();
}

class _EmojiBurstState extends State<EmojiBurst> {
  String? _previousEmoji;
  bool _wasGenerating = false;
  String? _pendingEmoji;
  OverlayEntry? _activeEntry;
  final GlobalKey _badgeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _previousEmoji = widget.emoji;
    _wasGenerating = widget.generating;
  }

  @override
  void didUpdateWidget(EmojiBurst old) {
    super.didUpdateWidget(old);

    if (widget.generating) {
      // During generation, note any emoji change but don't burst yet
      if (widget.emoji != _previousEmoji && widget.emoji != null) {
        _pendingEmoji = widget.emoji;
      }
    } else if (_wasGenerating && !widget.generating) {
      // Generation just finished — fire burst
      String? burstEmoji;
      if (_pendingEmoji != null) {
        burstEmoji = _pendingEmoji;
      } else if (widget.emoji != old.emoji && widget.emoji != null) {
        burstEmoji = widget.emoji;
      }
      if (burstEmoji != null && widget.enabled) {
        _triggerBurst(burstEmoji);
      }
      _pendingEmoji = null;
    }

    _previousEmoji = widget.emoji;
    _wasGenerating = widget.generating;
  }

  void _triggerBurst(String emoji) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _activeEntry?.remove();
      _activeEntry = null;

      final renderBox =
          _badgeKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return;

      final globalOffset = renderBox.localToGlobal(Offset.zero);
      final center = globalOffset + renderBox.size.center(Offset.zero);

      final overlay = Overlay.of(context);
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => IgnorePointer(
          child: _BurstOverlay(
            emoji: emoji,
            center: center,
            size: widget.size,
            onComplete: () {
              entry.remove();
              if (_activeEntry == entry) _activeEntry = null;
            },
          ),
        ),
      );
      _activeEntry = entry;
      overlay.insert(entry);
    });
  }

  @override
  void dispose() {
    _activeEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _badgeKey,
      child: widget.child,
    );
  }
}

class _ParticleConfig {
  final double dx;
  final double dy;
  final double delay;

  const _ParticleConfig({
    required this.dx,
    required this.dy,
    required this.delay,
  });
}

class _BurstOverlay extends StatefulWidget {
  final String emoji;
  final Offset center;
  final double size;
  final VoidCallback onComplete;

  const _BurstOverlay({
    required this.emoji,
    required this.center,
    required this.size,
    required this.onComplete,
  });

  @override
  State<_BurstOverlay> createState() => _BurstOverlayState();
}

class _BurstOverlayState extends State<_BurstOverlay>
    with SingleTickerProviderStateMixin {
  static const int _particleCount = 6;
  late final AnimationController _controller;
  late final Animation<double> _progress;
  late final List<_ParticleConfig> _particles;

  @override
  void initState() {
    super.initState();
    final random = Random();
    _particles = List.generate(_particleCount, (_) {
      // Leftward arc: 135° to 225°
      final angle = pi * 0.75 + random.nextDouble() * pi * 0.5;
      final distance = 80.0 + random.nextDouble() * 160.0;
      final delay = random.nextDouble() * 0.3;
      return _ParticleConfig(
        dx: cos(angle) * distance,
        dy: sin(angle) * distance,
        delay: delay,
      );
    });

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5500),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final p in _particles)
          AnimatedBuilder(
            animation: _controller,
            builder: (ctx, _) {
              final rawT = _progress.value;
              final t = rawT <= p.delay
                  ? 0.0
                  : ((rawT - p.delay) / (1.0 - p.delay)).clamp(0.0, 1.0);
              final opacity = 1.0 - t;
              final scale = t < 0.3
                  ? 1.0 + t * 1.0
                  : 1.3 - ((t - 0.3) / 0.7) * 1.3;

              final half = widget.size / 2;
              return Positioned(
                left: widget.center.dx + p.dx * t - half,
                top: widget.center.dy + p.dy * t - half,
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale.clamp(0.0, 1.5),
                    child: Text(
                      widget.emoji,
                      style: TextStyle(
                        fontSize: widget.size,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
