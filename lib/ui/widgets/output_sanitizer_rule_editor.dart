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

import 'package:front_porch_ai/models/output_sanitizer_rule.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/output_sanitizer_regex.dart';

/// Reusable find/replace rule editor for the Output Sanitizer.
///
/// Displays paired text fields for find and replace patterns, an add button,
/// the current rule list with drag-to-reorder handles, per-rule early-exit
/// toggles, and remove buttons.  The parent controls the data source and
/// persistence via [rules] and [onRulesChanged]; this widget owns the
/// controllers and validation state.
class OutputSanitizerRuleEditor extends StatefulWidget {
  const OutputSanitizerRuleEditor({
    super.key,
    required this.rules,
    required this.onRulesChanged,
    this.backgroundColor,
  });

  final List<OutputSanitizerRule> rules;
  final ValueChanged<List<OutputSanitizerRule>> onRulesChanged;

  /// Container background color. Defaults to [AppColors.cardOf].
  final Color? backgroundColor;

  @override
  State<OutputSanitizerRuleEditor> createState() =>
      _OutputSanitizerRuleEditorState();
}

class _OutputSanitizerRuleEditorState extends State<OutputSanitizerRuleEditor> {
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  bool _findError = false;

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  int _nextId(List<OutputSanitizerRule> rules) {
    if (rules.isEmpty) return 0;
    final max = rules.map((r) => r.id).reduce((a, b) => a > b ? a : b);
    // If you've somehow hit 9,223,372,036,854,775,807 rules,
    // congratulations — and please wrap around gracefully.
    return max == 0x7FFFFFFFFFFFFFFF ? 0 : max + 1;
  }

  void _addRule() {
    final find = _findController.text;
    final replace = _replaceController.text;
    if (find.isEmpty) return;
    if (!isValidFindPattern(find)) {
      setState(() => _findError = true);
      return;
    }
    if (widget.rules.any((r) => r.find == find && r.replace == replace)) return;
    widget.onRulesChanged([
      ...widget.rules,
      OutputSanitizerRule(
        id: _nextId(widget.rules),
        find: find,
        replace: replace,
      ),
    ]);
    _findController.clear();
    _replaceController.clear();
    setState(() => _findError = false);
  }

  void _removeRule(int index) {
    widget.onRulesChanged([...widget.rules]..removeAt(index));
  }

  // onReorderItem (unlike the retired onReorder) delivers newIndex already
  // adjusted for the removal at oldIndex — no manual decrement.
  void _reorderRule(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final list = [...widget.rules];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    widget.onRulesChanged(list);
  }

  void _toggleStopAfterMatch(int index) {
    final list = [...widget.rules];
    final old = list[index];
    list[index] = OutputSanitizerRule(
      id: old.id,
      find: old.find,
      replace: old.replace,
      stopAfterMatch: !old.stopAfterMatch,
    );
    widget.onRulesChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.backgroundColor ?? AppColors.cardOf(context);
    // Computed per build (a trivial scan of a handful of short strings) so
    // the warning is always current — a cached set went stale on first open.
    final dangerousRuleIds = {
      for (final r in widget.rules)
        if (hasNestedQuantifierInGroup(r.find)) r.id,
    };

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              // ── Find / Replace input row ──────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _findController,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 13,
                        ),
                        onChanged: (_) {
                          if (_findError) {
                            setState(() => _findError = false);
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'Find...',
                          hintStyle: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 13,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: _findError
                                  ? AppColors.negativeAccentOf(context)
                                  : AppColors.borderOf(context),
                            ),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: _findError
                                  ? AppColors.negativeAccentOf(context)
                                  : AppColors.borderOf(context),
                            ),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: _findError
                                  ? AppColors.negativeAccentOf(context)
                                  : AppColors.formMasterAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: AppColors.borderOf(context),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _replaceController,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Replace with...',
                          hintStyle: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 13,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.borderOf(context),
                            ),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.borderOf(context),
                            ),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.formMasterAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.add_circle,
                        color: AppColors.formMasterAccent,
                        size: 22,
                      ),
                      onPressed: _addRule,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.borderOf(context)),
              // ── Rule list (reorderable) ──────────────────────────
              if (widget.rules.isNotEmpty)
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: widget.rules.length,
                  onReorderItem: _reorderRule,
                  itemBuilder: (ctx, i) {
                    final rule = widget.rules[i];
                    return Container(
                      key: ValueKey('rule_${rule.id}'),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.borderOf(context),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: Icon(
                                Icons.drag_handle,
                                size: 18,
                                color: AppColors.textTertiary(context),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _toggleStopAfterMatch(i),
                              child: Tooltip(
                                message: rule.stopAfterMatch
                                    ? 'Stop after match (on)'
                                    : 'Stop after match (off)',
                                child: Icon(
                                  Icons.stop_circle,
                                  size: 18,
                                  color: rule.stopAfterMatch
                                      ? AppColors.formMasterAccent
                                      : AppColors.textTertiary(context),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (dangerousRuleIds.contains(rule.id))
                              Tooltip(
                                message:
                                    'This pattern may cause lag — nested quantifiers '
                                    'in capture groups can trigger catastrophic backtracking',
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 18,
                                  color: AppColors.porchHoneyOf(context),
                                ),
                              ),
                            if (dangerousRuleIds.contains(rule.id))
                              const SizedBox(width: 4),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    color: AppColors.textPrimary(context),
                                    fontSize: 13,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: rule.find,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: dangerousRuleIds.contains(rule.id)
                                            ? AppColors.porchHoneyOf(context)
                                            : null,
                                      ),
                                    ),
                                    const TextSpan(text: ' → '),
                                    TextSpan(text: rule.replace),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.remove_circle_outline,
                                color: AppColors.negativeAccentOf(context),
                                size: 22,
                              ),
                              onPressed: () => _removeRule(i),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        if (widget.rules.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'No rules configured',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${widget.rules.length} rule${widget.rules.length == 1 ? '' : 's'}',
              style: TextStyle(
                color: AppColors.porchHoneyOf(context),
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }
}
