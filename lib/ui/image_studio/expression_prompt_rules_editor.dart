// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

Future<ExpressionPromptRules?> showExpressionPromptRulesEditor(
  BuildContext context, {
  required ExpressionPromptRules rules,
  required ExpressionPromptRules Function() globalDefaults,
  required Future<void> Function(ExpressionPromptRules) saveDefaults,
  required Map<String, String> originals,
  String Function(String emotion, ExpressionPromptRules rules)? previewPrompt,
}) => showWarmDialogOf<ExpressionPromptRules>(
  context,
  builder: (_) => ExpressionPromptRulesEditor(
    rules: rules,
    globalDefaults: globalDefaults,
    saveDefaults: saveDefaults,
    originals: originals,
    previewPrompt: previewPrompt,
  ),
);

class ExpressionPromptRulesEditor extends StatefulWidget {
  const ExpressionPromptRulesEditor({
    super.key,
    required this.rules,
    required this.globalDefaults,
    required this.saveDefaults,
    required this.originals,
    this.previewPrompt,
  });
  final ExpressionPromptRules rules;
  final ExpressionPromptRules Function() globalDefaults;
  final Future<void> Function(ExpressionPromptRules) saveDefaults;
  final Map<String, String> originals;
  final String Function(String emotion, ExpressionPromptRules rules)?
  previewPrompt;
  @override
  State<ExpressionPromptRulesEditor> createState() =>
      _ExpressionPromptRulesEditorState();
}

class _ExpressionPromptRulesEditorState
    extends State<ExpressionPromptRulesEditor> {
  late final TextEditingController _prefix = TextEditingController(
    text: widget.rules.prefix,
  );
  late final TextEditingController _suffix = TextEditingController(
    text: widget.rules.suffix,
  );
  late List<ExpressionPromptReplacement> _rows = [...widget.rules.replacements];
  String? _error;
  String? _status;
  bool _saving = false;
  @override
  void dispose() {
    _prefix.dispose();
    _suffix.dispose();
    super.dispose();
  }

  ExpressionPromptRules _rules() => ExpressionPromptRules(
    prefix: _prefix.text,
    suffix: _suffix.text,
    replacements: _rows,
  );
  void _reset() {
    final r = widget.globalDefaults();
    setState(() {
      _prefix.text = r.prefix;
      _suffix.text = r.suffix;
      _rows = [...r.replacements];
      _error = null;
      _status = null;
    });
  }

  Future<void> _edit([int? index]) async {
    final row = index == null ? null : _rows[index];
    final find = TextEditingController(text: row?.find ?? '');
    final replace = TextEditingController(text: row?.replace ?? '');
    // The buttons live outside the body, so the two values they share with
    // it are notifiers rather than a StatefulBuilder's locals.
    final sensitive = ValueNotifier<bool>(row?.caseSensitive ?? true);
    final error = ValueNotifier<String?>(null);
    final result = await showWarmDialog<ExpressionPromptReplacement>(
      context,
      title: 'Literal replacement',
      width: 420,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: find,
            decoration: const InputDecoration(labelText: 'Find'),
            maxLength: 2048,
          ),
          TextField(
            controller: replace,
            decoration: const InputDecoration(labelText: 'Replace with'),
            maxLength: 2048,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: sensitive,
            builder: (_, value, _) => CheckboxListTile(
              value: value,
              title: const Text('Case sensitive'),
              onChanged: (v) => sensitive.value = v ?? true,
            ),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: error,
            builder: (_, message, _) =>
                message == null ? const SizedBox.shrink() : Text(message),
          ),
        ],
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          label: 'Use replacement',
          onPressed: () {
            try {
              Navigator.pop(
                context,
                ExpressionPromptReplacement(
                  find: find.text,
                  replace: replace.text,
                  caseSensitive: sensitive.value,
                ),
              );
            } on FormatException catch (e) {
              error.value = e.message;
            }
          },
        ),
      ],
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    find.dispose();
    replace.dispose();
    sensitive.dispose();
    error.dispose();
    if (!mounted || result == null) return;
    setState(() {
      _status = null;
      if (index == null) {
        _rows.add(result);
      } else {
        _rows[index] = result;
      }
    });
  }

  void _move(int from, int to) => setState(() {
    _status = null;
    final r = _rows.removeAt(from);
    _rows.insert(to, r);
  });
  @override
  Widget build(BuildContext context) {
    ExpressionPromptRules? preview;
    String? validationError;
    try {
      preview = _rules();
      for (final original in widget.originals.entries) {
        widget.previewPrompt?.call(original.key, preview) ??
            preview.apply(original.value);
      }
    } on FormatException catch (e) {
      validationError = e.message;
      preview = null;
    }
    return WarmDialog(
      title: 'Prompt rules',
      width: 620,
      content: SizedBox(
        height: 470,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Positive prompts only. Replacements run in order, then prefix and suffix are added. Prompts edited for a single expression keep their own wording.',
              ),
              TextField(
                controller: _prefix,
                enabled: !_saving,
                maxLength: 4096,
                decoration: const InputDecoration(
                  labelText: 'Text before each prompt',
                ),
                onChanged: (_) => setState(() {
                  _error = null;
                  _status = null;
                }),
              ),
              TextField(
                controller: _suffix,
                enabled: !_saving,
                maxLength: 4096,
                decoration: const InputDecoration(
                  labelText: 'Text after each prompt',
                ),
                onChanged: (_) => setState(() {
                  _error = null;
                  _status = null;
                }),
              ),
              for (var i = 0; i < _rows.length; i++)
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _saving ? null : () => _edit(i),
                        child: Text(
                          '${i + 1}. ${_rows[i].find} -> ${_rows[i].replace} (${_rows[i].caseSensitive ? 'case sensitive' : 'ignore case'})',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Move up',
                      onPressed: !_saving && i > 0
                          ? () => _move(i, i - 1)
                          : null,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Move down',
                      onPressed: !_saving && i < _rows.length - 1
                          ? () => _move(i, i + 1)
                          : null,
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    IconButton(
                      tooltip: 'Delete replacement',
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _rows.removeAt(i);
                              _status = null;
                            }),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              TextButton(
                onPressed: !_saving && _rows.length < 32 ? () => _edit() : null,
                child: const Text('Add replacement'),
              ),
              if (validationError != null) Text(validationError),
              if (_error != null) Text(_error!),
              if (_status != null) Text(_status!),
              for (final e in widget.originals.entries)
                ExpansionTile(
                  title: Text(e.key),
                  children: [
                    const Text('Original'),
                    SelectableText(e.value),
                    const Text('Effective'),
                    SelectableText(
                      preview == null
                          ? e.value
                          : (widget.previewPrompt?.call(e.key, preview) ??
                                preview.apply(e.value)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _reset,
          child: const Text('Reset to global defaults'),
        ),
        TextButton(
          onPressed: _saving || preview == null
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    await widget.saveDefaults(_rules());
                    if (mounted) {
                      setState(() => _status = 'Global defaults saved.');
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() => _error = 'Could not save defaults: $e');
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _saving = false);
                    }
                  }
                },
          child: const Text('Save as global defaults'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.formMasterAccent,
            foregroundColor: AppColors.onChaosAccent,
          ),
          onPressed: preview == null || _saving
              ? null
              : () => Navigator.pop(context, _rules()),
          child: const Text('Use for this pack'),
        ),
      ],
    );
  }
}
