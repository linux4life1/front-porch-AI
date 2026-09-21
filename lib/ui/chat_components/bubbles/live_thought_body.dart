// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Thought pane: cap height. followLatest is opt-in only — chat passes
// false (option B: the user scrolls the think box themselves). The
// widget still can follow if a host asks.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

const double kLiveThoughtMaxHeight = 160;

class LiveThoughtBody extends StatefulWidget {
  const LiveThoughtBody({
    super.key,
    required this.text,
    required this.followLatest,
  });

  final String text;
  final bool followLatest;

  @override
  State<LiveThoughtBody> createState() => _LiveThoughtBodyState();
}

class _LiveThoughtBodyState extends State<LiveThoughtBody> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.followLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LiveThoughtBody old) {
    super.didUpdateWidget(old);
    if (widget.followLatest && old.text != widget.text && _atEnd()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
    }
  }

  void _jumpToEnd() {
    if (!_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    if (max > 0) _controller.jumpTo(max);
  }

  bool _atEnd() {
    if (!_controller.hasClients) return true;
    final pos = _controller.position;
    return pos.maxScrollExtent - pos.pixels < 24;
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: kLiveThoughtMaxHeight),
      child: SingleChildScrollView(
        key: const Key('live-thought-scroll'),
        controller: _controller,
        child: Text(
          widget.text,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
          ),
        ),
      ),
    );
  }
}
