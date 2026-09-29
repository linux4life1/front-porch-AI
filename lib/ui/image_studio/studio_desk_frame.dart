// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Left rail and stove. Wide windows sit them side by side. Narrow
/// windows stack the same blocks.
class StudioDeskFrame extends StatelessWidget {
  const StudioDeskFrame({
    super.key,
    this.subject,
    this.prompt = '',
    this.promptController,
    this.onPromptChanged,
    required this.well,
    required this.packNote,
    this.onExpressionPack,
    this.picture,
    required this.stove,
    this.output,
    this.below,
  });

  final Widget? subject;
  final String prompt;
  final TextEditingController? promptController;
  final ValueChanged<String>? onPromptChanged;
  final String well;
  final String packNote;
  final VoidCallback? onExpressionPack;
  final Widget? picture;
  final Widget stove;

  /// Finished picture. A wide desk puts it under Expression pack. A narrow
  /// desk keeps it under the stove.
  final Widget? output;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final fill = wide && constraints.maxHeight.isFinite;
        final rail = _StudioRail(
          subject: subject,
          prompt: prompt,
          promptController: promptController,
          onPromptChanged: onPromptChanged,
          well: well,
          packNote: packNote,
          onExpressionPack: onExpressionPack,
          picture: picture,
          output: fill ? null : (wide ? output : null),
        );
        if (fill) {
          return Row(
            key: const Key('studio-desk-wide'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 115,
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      rail,
                      if (output != null)
                        KeyedSubtree(
                          key: const Key('studio-desk-output'),
                          child: output!,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 85,
                child: SingleChildScrollView(primary: false, child: stove),
              ),
            ],
          );
        }
        final narrowOutput = !wide && output != null
            ? <Widget>[const SizedBox(height: 16), output!]
            : const <Widget>[];
        final body = wide
            ? Row(
                key: const Key('studio-desk-wide'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 115, child: rail),
                  const SizedBox(width: 16),
                  Expanded(flex: 85, child: stove),
                ],
              )
            : Column(
                key: const Key('studio-desk-narrow'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  rail,
                  const SizedBox(height: 16),
                  stove,
                  ...narrowOutput,
                ],
              );
        if (below == null) return body;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [body, const SizedBox(height: 16), below!],
        );
      },
    );
  }
}

class _StudioRail extends StatelessWidget {
  const _StudioRail({
    required this.subject,
    required this.prompt,
    required this.promptController,
    required this.onPromptChanged,
    required this.well,
    required this.packNote,
    required this.onExpressionPack,
    required this.picture,
    required this.output,
  });

  final Widget? subject;
  final String prompt;
  final TextEditingController? promptController;
  final ValueChanged<String>? onPromptChanged;
  final String well;
  final String packNote;
  final VoidCallback? onExpressionPack;
  final Widget? picture;
  final Widget? output;

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?subject,
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Prompt',
              style: TextStyle(
                color: secondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            TextButton(onPressed: () {}, child: const Text('Write it for me')),
          ],
        ),
        _PromptBox(
          prompt: prompt,
          controller: promptController,
          onChanged: onPromptChanged,
        ),
        const SizedBox(height: 12),
        Text(well, style: TextStyle(color: secondary, height: 1.35)),
        ?picture,
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            TextButton(
              onPressed: onExpressionPack,
              child: const Text('Expression pack'),
            ),
            Text(packNote, style: TextStyle(color: secondary, fontSize: 12)),
          ],
        ),
        if (output != null) ...[
          const SizedBox(height: 12),
          KeyedSubtree(key: const Key('studio-desk-output'), child: output!),
        ],
      ],
    );
  }
}

class _PromptBox extends StatefulWidget {
  const _PromptBox({required this.prompt, this.controller, this.onChanged});

  final String prompt;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  State<_PromptBox> createState() => _PromptBoxState();
}

class _PromptBoxState extends State<_PromptBox> {
  TextEditingController? _own;

  TextEditingController get _box => widget.controller ?? _own!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _own = TextEditingController(text: widget.prompt);
    }
  }

  @override
  void didUpdateWidget(_PromptBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    final own = _own;
    if (own != null && widget.prompt != own.text) {
      own.value = TextEditingValue(
        text: widget.prompt,
        selection: TextSelection.collapsed(offset: widget.prompt.length),
      );
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _box,
      minLines: 3,
      maxLines: 6,
      onChanged: widget.onChanged,
      style: TextStyle(color: AppColors.textPrimary(context)),
      decoration: const InputDecoration(
        isDense: true,
        hintText: 'Describe the portrait',
      ),
    );
  }
}
