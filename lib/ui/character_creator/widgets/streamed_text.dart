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
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Text still streaming in, coloured the way the finished box will colour
/// it (`{{char}}` teal, speech honey, *narration* in the narration tone:
/// `StyledTextPreset.studioProse`), with the spec's 2×16 amber caret after
/// it when [caret].
///
/// The spans come from the same tokenizer the boxes use, through a
/// controller made with the text and dropped at once: made with its text it
/// queues no spell-check pass.
class StreamedText extends StatelessWidget {
  const StreamedText({
    super.key,
    required this.text,
    required this.style,
    this.caret = true,
  });

  final String text;
  final TextStyle style;
  final bool caret;

  @override
  Widget build(BuildContext context) {
    final controller = StyledTextController(
      text: text,
      preset: StyledTextPreset.studioProse,
    );
    final coloured = controller.buildTextSpan(
      context: context,
      style: style,
      withComposing: false,
    );
    controller.dispose();
    return Text.rich(
      TextSpan(
        children: [
          coloured,
          if (caret)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                width: 2,
                height: 16,
                margin: const EdgeInsets.only(left: 2),
                color: StudioColors.amberOf(context),
              ),
            ),
        ],
      ),
      style: style,
    );
  }
}
