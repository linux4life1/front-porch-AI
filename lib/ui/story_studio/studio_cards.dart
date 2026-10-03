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

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/story_studio/studio_buttons.dart';
import 'package:front_porch_ai/ui/story_studio/studio_theme.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

// Cards, dialogs and the small status pieces of the spec.

/// The card (`wc`): card fill, hairline, radius 10, padding 12×14, gap 8.
/// [selected] adds the amber border + ring; [raised] uses the raised fill.
class StoryCard extends StatelessWidget {
  final List<Widget> children;
  final bool selected;
  final bool raised;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final CrossAxisAlignment alignment;

  const StoryCard({
    super.key,
    required this.children,
    this.selected = false,
    this.raised = false,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
    this.onTap,
    this.alignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: raised
            ? StudioColors.raiseOf(context)
            : StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? amber : StudioColors.lineOf(context),
        ),
        boxShadow: selected
            ? [BoxShadow(color: amber, spreadRadius: 1, blurRadius: 0)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            children[i],
          ],
        ],
      ),
    );
    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: box,
    );
  }
}

/// A row with 10px gaps that wraps on narrow widths.
class StoryRow extends StatelessWidget {
  final List<Widget> children;
  final bool wrap;

  const StoryRow({super.key, required this.children, this.wrap = true});

  @override
  Widget build(BuildContext context) => wrap
      ? Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        )
      : Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              children[i],
            ],
          ],
        );
}

/// The 4px progress bar: line track, amber fill (teal when [done]).
class StoryProgressBar extends StatelessWidget {
  final double fraction;
  final bool done;

  const StoryProgressBar(this.fraction, {super.key, this.done = false});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: LinearProgressIndicator(
      value: fraction.clamp(0, 1),
      minHeight: 4,
      backgroundColor: StudioColors.lineOf(context),
      color: done
          ? StudioColors.tealOf(context)
          : StudioColors.amberOf(context),
    ),
  );
}

/// Step dots: 20px circles with a mono digit; done = honey, current = amber.
class StoryStepDots extends StatelessWidget {
  final List<String> steps;
  final int current;
  final ValueChanged<int>? onTap;

  const StoryStepDots({
    super.key,
    required this.steps,
    required this.current,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < steps.length; i++) ...[
        if (i > 0) const SizedBox(width: 14),
        InkWell(
          key: ValueKey('story-step-$i'),
          onTap: onTap == null ? null : () => onTap!(i),
          borderRadius: BorderRadius.circular(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < current
                      ? StudioColors.honeyOf(context)
                      : i == current
                      ? StudioColors.amberOf(context)
                      : null,
                  border: i > current
                      ? Border.all(color: StudioColors.lineOf(context))
                      : null,
                ),
                alignment: Alignment.center,
                child: i < current
                    ? Icon(
                        Icons.check,
                        size: 12,
                        color: StudioColors.amberInkOf(context),
                      )
                    : Text(
                        '${i + 1}',
                        style: StudioType.mono(
                          context,
                          size: 10,
                          color: i == current
                              ? StudioColors.amberInkOf(context)
                              : StudioColors.mutedOf(context),
                        ),
                      ),
              ),
              const SizedBox(height: 3),
              Text(
                steps[i],
                style: StudioType.ui(
                  context,
                  size: 10.5,
                  color: i == current
                      ? StudioColors.inkOf(context)
                      : StudioColors.mutedOf(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

/// Portrait or initials on the warm gradient, 36px (52px when [large]).
class StoryAvatar extends StatelessWidget {
  final String name;
  final String? imagePath;
  final bool large;

  const StoryAvatar(this.name, {super.key, this.imagePath, this.large = false});

  @override
  Widget build(BuildContext context) {
    final size = large ? 52.0 : 36.0;
    final radius = BorderRadius.circular(large ? 10 : 9);
    final path = imagePath;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: path != null && path.isNotEmpty
            ? Image.file(File(path), fit: BoxFit.cover)
            : Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      StudioColors.portraitStart,
                      StudioColors.portraitEnd,
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: StudioType.ui(
                    context,
                    size: large ? 17 : 13,
                    weight: FontWeight.w700,
                    color: StudioColors.honeyOf(context),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Empty state inside a card: title, one line of help, one action.
class StoryEmptyState extends StatelessWidget {
  final String title;
  final String detail;
  final String? action;
  final VoidCallback? onAction;

  const StoryEmptyState({
    super.key,
    required this.title,
    required this.detail,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => StoryCard(
    children: [
      Text(title, style: StudioType.ui(context, weight: FontWeight.w700)),
      Text(
        detail,
        style: StudioType.ui(
          context,
          size: 12.5,
          color: StudioColors.mutedOf(context),
        ),
      ),
      if (action != null) StoryButton.primary(action!, onPressed: onAction),
    ],
  );
}

/// The studio dialog: card fill, radius 12, 15/700 title, muted body, ghost
/// Cancel + primary (or danger) confirm. Resolves true when confirmed.
Future<bool> showStoryConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showStoryDialog<bool>(
    context,
    title: title,
    body: Text(
      body,
      style: StudioType.ui(
        context,
        size: 12.5,
        color: StudioColors.mutedOf(context),
      ),
    ),
    actions: (ctx) => [
      StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
      destructive
          ? StoryButton.danger(
              confirmLabel,
              onPressed: () => Navigator.pop(ctx, true),
            )
          : StoryButton.primary(
              confirmLabel,
              onPressed: () => Navigator.pop(ctx, true),
            ),
    ],
  );
  return ok == true;
}

/// A studio dialog with arbitrary body and actions.
Future<T?> showStoryDialog<T>(
  BuildContext context, {
  required String title,
  required Widget body,
  required List<Widget> Function(BuildContext ctx) actions,
  double width = 380,
}) => showDialog<T>(
  context: context,
  builder: (ctx) => StudioTheme(
    child: Dialog(
      backgroundColor: StudioColors.cardOf(ctx),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: StudioColors.lineOf(ctx)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: StudioType.ui(ctx, size: 15, weight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Flexible(child: SingleChildScrollView(child: body)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final a in actions(ctx)) ...[
                    const SizedBox(width: 8),
                    a,
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
