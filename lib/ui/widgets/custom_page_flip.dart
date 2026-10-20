import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import 'package:front_porch_ai/ui/theme/theme.dart';

class CustomPageFlip extends StatefulWidget {
  final List<Widget> pages;
  final int initialPage;
  final ValueChanged<int>? onPageFlipped;
  final VoidCallback? onFlipStart;
  final Widget? backCover;

  const CustomPageFlip({
    super.key,
    required this.pages,
    this.initialPage = 0,
    this.onPageFlipped,
    this.onFlipStart,
    this.backCover,
  });

  @override
  State<CustomPageFlip> createState() => CustomPageFlipState();
}

class CustomPageFlipState extends State<CustomPageFlip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _currentPage = 0;
  bool _isTurning = false;
  bool _turningForward = true;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 600),
          )
          ..addListener(() {
            setState(() {});
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              setState(() {
                _isTurning = false;
                if (_turningForward && _currentPage < widget.pages.length - 1) {
                  _currentPage++;
                  widget.onPageFlipped?.call(_currentPage);
                } else if (!_turningForward && _currentPage > 0) {
                  _currentPage--;
                  widget.onPageFlipped?.call(_currentPage);
                }
              });
              _controller.reset();
            }
          });
  }

  @override
  void didUpdateWidget(CustomPageFlip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPage != oldWidget.initialPage) {
      _currentPage = widget.initialPage;
    } else if (_currentPage >= widget.pages.length) {
      _currentPage = math.max(0, widget.pages.length - 1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void nextPage() {
    if (_isTurning || _currentPage >= widget.pages.length - 1) return;
    widget.onFlipStart?.call();
    setState(() {
      _isTurning = true;
      _turningForward = true;
    });
    // Add a natural bezier curve to the animation
    _controller.animateTo(1.0, curve: Curves.easeOutCubic);
  }

  void previousPage() {
    if (_isTurning || _currentPage <= 0) return;
    widget.onFlipStart?.call();
    setState(() {
      _isTurning = true;
      _turningForward = false;
    });
    // Set controller to 1.0 and animate reverse
    _controller.value = 1.0;
    _controller.animateTo(0.0, curve: Curves.easeOutCubic);
  }

  /// Jump directly to a specific page index (no animation).
  void goToPage(int page) {
    if (_isTurning) return;
    final targetPage = page.clamp(0, widget.pages.length - 1);
    if (targetPage == _currentPage) return;
    setState(() {
      _currentPage = targetPage;
      _controller.value = 0.0;
    });
    widget.onPageFlipped?.call(targetPage);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();

    final width = MediaQuery.of(context).size.width;
    final isTwoPageSpread = width > 800;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! < -300) {
          nextPage();
        } else if (details.primaryVelocity! > 300) {
          previousPage();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!_isTurning) {
            // Static view when not turning
            return Stack(
              children: [
                // Display the current page(s)
                Positioned.fill(child: widget.pages[_currentPage]),

                // Tap zones for navigation
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 100,
                  child: GestureDetector(
                    onTap: previousPage,
                    behavior: HitTestBehavior.translucent,
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 100,
                  child: GestureDetector(
                    onTap: nextPage,
                    behavior: HitTestBehavior.translucent,
                  ),
                ),
              ],
            );
          }

          // Render animation state
          final ratio = _controller.value;

          Widget currentPageWidget;
          Widget nextOrPrevPageWidget;

          if (_turningForward) {
            currentPageWidget = widget.pages[_currentPage];
            nextOrPrevPageWidget = _currentPage + 1 < widget.pages.length
                ? widget.pages[_currentPage + 1]
                : (widget.backCover ?? Container(color: Colors.transparent));
          } else {
            currentPageWidget = widget.pages[_currentPage];
            nextOrPrevPageWidget = widget.pages[_currentPage - 1];
          }

          // Build a 3D door-hinge transition with realistic shadows
          return Stack(
            children: [
              // 1. The page underneath layer (the one being revealed)
              Positioned.fill(child: nextOrPrevPageWidget),

              // 2. The shadow cast BY the turning page ON the page underneath
              Positioned.fill(
                child: CustomPaint(
                  painter: _CastShadowPainter(
                    progress: _turningForward ? ratio : 1.0 - ratio,
                    isForward: _turningForward,
                    isTwoPageSpread: isTwoPageSpread,
                  ),
                ),
              ),

              // 3. The page being turned (3D transform)
              Positioned.fill(
                child: Transform(
                  alignment: isTwoPageSpread
                      ? Alignment.center
                      : (_turningForward
                            ? Alignment.centerLeft
                            : Alignment.centerRight),
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001) // Perspective
                    ..rotateY(
                      (_turningForward ? -math.pi : math.pi) *
                          (_turningForward ? ratio : 1.0 - ratio),
                    ),
                  child: ClipRect(
                    clipper: _HalfPageClipper(
                      isRightHalf: _turningForward,
                      isTwoPageSpread: isTwoPageSpread,
                    ),
                    child: Stack(
                      children: [
                        // The actual content of the turning page
                        currentPageWidget,

                        // Specular highlight / self-shadowing on the turning page itself
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _SelfShadowPainter(
                                progress: _turningForward ? ratio : 1.0 - ratio,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Tap zones during turn (prevents multi-taps breaking state)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {},
                  behavior: HitTestBehavior.translucent,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HalfPageClipper extends CustomClipper<Rect> {
  final bool isRightHalf;
  final bool isTwoPageSpread;

  _HalfPageClipper({required this.isRightHalf, required this.isTwoPageSpread});

  @override
  Rect getClip(Size size) {
    if (!isTwoPageSpread) return Rect.fromLTWH(0, 0, size.width, size.height);

    if (isRightHalf) {
      return Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height);
    } else {
      return Rect.fromLTWH(0, 0, size.width / 2, size.height);
    }
  }

  @override
  bool shouldReclip(_HalfPageClipper oldClipper) {
    return oldClipper.isRightHalf != isRightHalf ||
        oldClipper.isTwoPageSpread != isTwoPageSpread;
  }
}

class _CastShadowPainter extends CustomPainter {
  final double progress;
  final bool isForward;
  final bool isTwoPageSpread;

  _CastShadowPainter({
    required this.progress,
    required this.isForward,
    required this.isTwoPageSpread,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final spineX = isTwoPageSpread ? size.width / 2 : 0.0;
    final turningWidth = isTwoPageSpread ? size.width / 2 : size.width;

    // As page lifts, shadow grows wider but lighter
    final maxShadowWidth = turningWidth * 0.3;
    final currentShadowWidth = maxShadowWidth * math.sin(progress * math.pi);

    final gradientOpacity = 0.4 * (1.0 - math.sin(progress * math.pi / 2));

    if (currentShadowWidth <= 0.01) return;

    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(spineX, 0),
        Offset(
          spineX + (isForward ? -currentShadowWidth : currentShadowWidth),
          0,
        ),
        [InkColors.dim(gradientOpacity), Colors.transparent],
      );

    canvas.drawRect(
      isForward
          ? Rect.fromLTWH(
              spineX - currentShadowWidth,
              0,
              currentShadowWidth,
              size.height,
            )
          : Rect.fromLTWH(spineX, 0, currentShadowWidth, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CastShadowPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isForward != isForward;
}

class _SelfShadowPainter extends CustomPainter {
  final double progress;

  _SelfShadowPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // Adds a shine/shadow to the bending paper curve
    final opacity = 0.3 * math.sin(progress * math.pi);

    final paint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(size.width, 0),
        [
          Colors.transparent,
          // theme-keep: the paper's specular highlight.
          Colors.white.withValues(alpha: opacity * 0.6),
          InkColors.dim(opacity * 0.3), // Core shadow
          Colors.transparent,
        ],
        [0.0, 0.4, 0.8, 1.0],
      );

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_SelfShadowPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
