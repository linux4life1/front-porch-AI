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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Reusable stop-sequence list editor.
///
/// Displays a text field for adding sequences and the current list with remove
/// buttons. The parent controls the data source and persistence via [sequences]
/// and [onSequencesChanged]; this widget owns the controller.
class StopSequenceList extends StatefulWidget {
  const StopSequenceList({
    super.key,
    required this.sequences,
    required this.onSequencesChanged,
    this.backgroundColor,
  });

  final List<String> sequences;
  final ValueChanged<List<String>> onSequencesChanged;

  /// Container background color. Defaults to [AppColors.cardOf].
  final Color? backgroundColor;

  @override
  State<StopSequenceList> createState() => _StopSequenceListState();
}

class _StopSequenceListState extends State<StopSequenceList> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String val) {
    if (val.isEmpty) return;
    widget.onSequencesChanged([...widget.sequences, val]);
    _controller.clear();
  }

  void _remove(String seq) {
    widget.onSequencesChanged([...widget.sequences]..remove(seq));
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ?? AppColors.cardOf(context);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                    decoration: InputDecoration(
                      hintText: 'Add stop sequence...',
                      hintStyle: TextStyle(
                        color: AppColors.textTertiary(context),
                      ),
                      border: InputBorder.none,
                    ),
                    onSubmitted: _add,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.add_circle,
                    color: AppColors.formAccentOf(context),
                    size: 22,
                  ),
                  onPressed: () => _add(_controller.text),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.borderOf(context)),
          ...widget.sequences.map(
            (seq) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      seq.replaceAll('\n', '\\n'),
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: AppColors.negativeAccentOf(context),
                      size: 22,
                    ),
                    onPressed: () => _remove(seq),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
