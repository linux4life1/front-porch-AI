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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The spec's hint box (docs/design/creator-ui-spec.md, "Hint box"): `raise`
/// fill, a 1px amber edge at 50%, radius 12, padding 16×18; an info icon,
/// a title and a body, then an outlined action (with its running label) and
/// a quiet keep. Nothing is changed until the user picks one. The body of
/// both hints: the outfit after a new first message, and the greetings
/// after a new profile.
class CreatorHintBox extends StatelessWidget {
  const CreatorHintBox({
    super.key,
    required this.title,
    required this.body,
    required this.action,
    required this.actionRunning,
    required this.keep,
    required this.running,
    required this.onAction,
    required this.onKeep,
    this.actionKey,
    this.keepKey,
    this.error,
    this.errorKey,
  });

  final String title;
  final String body;

  /// The outlined button's label, and its label while [running].
  final String action;
  final String actionRunning;
  final String keep;
  final bool running;
  final VoidCallback onAction;
  final VoidCallback onKeep;
  final Key? actionKey;
  final Key? keepKey;
  final String? error;
  final Key? errorKey;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: StudioColors.inkOf(context),
          ),
        ),
        Text(
          body,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: StudioColors.proseOf(context),
          ),
        ),
        if (error != null)
          Text(
            error!,
            key: errorKey,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: StudioColors.badOf(context),
            ),
          ),
      ],
    );
    final buttons = [
      SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          key: actionKey,
          onPressed: running ? null : onAction,
          icon: running
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: amber,
                  ),
                )
              : const Icon(Icons.refresh, size: 18),
          label: Text(
            running ? actionRunning : action,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: amber,
            disabledForegroundColor: amber,
            side: BorderSide(color: amber, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
      SizedBox(
        height: 40,
        child: TextButton(
          key: keepKey,
          onPressed: running ? null : onKeep,
          style: TextButton.styleFrom(
            foregroundColor: StudioColors.proseOf(context),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            keep,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: StudioColors.raiseOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final icon = Icon(Icons.info_outline, size: 22, color: amber);
          // The sketch wraps: the buttons share the line only when the
          // words keep at least 360 of it.
          if (c.maxWidth >= 22 + 360 + 400) {
            return Row(
              spacing: 12,
              children: [
                icon,
                Expanded(child: text),
                ...buttons,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  icon,
                  Expanded(child: text),
                ],
              ),
              Wrap(spacing: 18, runSpacing: 8, children: buttons),
            ],
          );
        },
      ),
    );
  }
}
