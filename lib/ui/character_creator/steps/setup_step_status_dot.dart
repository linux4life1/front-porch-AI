// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'setup_step.dart';

/// An 8px pulsing status dot that blinks during transitional states.
/// Uses the same animation pattern as LogView (800ms easeInOut opacity pulse).
class _BackendStatusDot extends StatefulWidget {
  final Color color;
  final bool isBlinking;

  const _BackendStatusDot({required this.color, required this.isBlinking});

  @override
  State<_BackendStatusDot> createState() => _BackendStatusDotState();
}

class _BackendStatusDotState extends State<_BackendStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _updateBlinking();
  }

  @override
  void didUpdateWidget(_BackendStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isBlinking != widget.isBlinking) {
      _updateBlinking();
    }
  }

  void _updateBlinking() {
    if (widget.isBlinking) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: _animation.value),
          ),
        );
      },
    );
  }
}
