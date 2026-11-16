// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/app_corners.dart';

/// Settings → General → the block under the Fallback system prompt.
///
/// Flat on purpose (prompt-picker SOW Phase 0): it would be the only
/// accordion in Settings, and the additions belong beside the base prompt
/// they extend, not behind a tap.
class GlobalPromptAdditions extends StatefulWidget {
  const GlobalPromptAdditions({super.key});

  @override
  State<GlobalPromptAdditions> createState() => _GlobalPromptAdditionsState();
}

class _GlobalPromptAdditionsState extends State<GlobalPromptAdditions> {
  late final TextEditingController _sysController;
  late final TextEditingController _postController;
  late final FocusNode _sysFocus;
  late final FocusNode _postFocus;

  @override
  void initState() {
    super.initState();
    final settings = context.read<StorageService>().generationSettings;
    _sysController = TextEditingController(
      text: settings.additionalSystemPrompt,
    );
    _postController = TextEditingController(
      text: settings.additionalPostHistoryInstructions,
    );
    _sysFocus = FocusNode();
    _postFocus = FocusNode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.read<StorageService>().generationSettings;
    if (!_sysFocus.hasFocus &&
        _sysController.text != settings.additionalSystemPrompt) {
      _sysController.text = settings.additionalSystemPrompt;
    }
    if (!_postFocus.hasFocus &&
        _postController.text != settings.additionalPostHistoryInstructions) {
      _postController.text = settings.additionalPostHistoryInstructions;
    }
  }

  @override
  void dispose() {
    _sysController.dispose();
    _postController.dispose();
    _sysFocus.dispose();
    _postFocus.dispose();
    super.dispose();
  }

  Future<void> _save(Future<void> action) async {
    try {
      await action;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save prompt addition: $error')),
      );
    }
  }

  String _appendSmartMacro(String current, String macro) {
    if (current.isEmpty) return macro;
    if (RegExp(r'\s$').hasMatch(current)) return '$current$macro';
    return '$current $macro';
  }

  void _insertMacro(
    TextEditingController controller,
    FocusNode focusNode,
    String macro,
    Future<void> Function(String) persist,
  ) {
    final current = controller.text;
    final selection = controller.selection;
    final String next;
    final int nextOffset;

    if (focusNode.hasFocus && selection.isValid) {
      final start = selection.start.clamp(0, current.length);
      final end = selection.end.clamp(0, current.length);
      final lo = start < end ? start : end;
      final hi = start < end ? end : start;
      next = current.replaceRange(lo, hi, macro);
      nextOffset = lo + macro.length;
    } else {
      next = _appendSmartMacro(current, macro);
      nextOffset = next.length;
      focusNode.requestFocus();
    }

    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _save(persist(next));
  }

  Widget _macroRow({
    required String fieldKeyPrefix,
    required TextEditingController controller,
    required FocusNode focusNode,
    required Future<void> Function(String) persist,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Available macros:',
          style: TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary(context),
          ),
        ),
        _MacroInsertChip(
          key: ValueKey('$fieldKeyPrefix-macro-char'),
          macro: '{{char}}',
          description: 'Character',
          tooltip: 'Inserts character name at runtime',
          onTap: () => _insertMacro(controller, focusNode, '{{char}}', persist),
        ),
        _MacroInsertChip(
          key: ValueKey('$fieldKeyPrefix-macro-user'),
          macro: '{{user}}',
          description: 'User',
          tooltip: 'Inserts user persona name at runtime',
          onTap: () => _insertMacro(controller, focusNode, '{{user}}', persist),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StorageService>().generationSettings;
    final corners = AppCorners.of(context);
    return Material(
      color: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: corners.circular(12),
        side: BorderSide(color: AppColors.borderOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Global prompt additions',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Saved automatically. Leave blank to disable. Both fields support {{char}} and {{user}}.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              _macroRow(
                fieldKeyPrefix: 'sys-additions',
                controller: _sysController,
                focusNode: _sysFocus,
                persist: settings.setAdditionalSystemPrompt,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _sysController,
                focusNode: _sysFocus,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Additional system instructions',
                  helperText:
                      'Appended to the selected system prompt, including character and group prompts.',
                  helperMaxLines: 3,
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) =>
                    _save(settings.setAdditionalSystemPrompt(value)),
              ),
              const SizedBox(height: 16),
              _macroRow(
                fieldKeyPrefix: 'post-additions',
                controller: _postController,
                focusNode: _postFocus,
                persist: settings.setAdditionalPostHistoryInstructions,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _postController,
                focusNode: _postFocus,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Additional post-history instructions',
                  helperText:
                      'Appended after existing post-history instructions.',
                  helperMaxLines: 3,
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) =>
                    _save(settings.setAdditionalPostHistoryInstructions(value)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroInsertChip extends StatelessWidget {
  const _MacroInsertChip({
    super.key,
    required this.macro,
    required this.description,
    required this.tooltip,
    required this.onTap,
  });

  final String macro;
  final String description;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(6);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: 'Insert $macro ($description)',
        child: Material(
          color: AppColors.surfaceContainerOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(color: AppColors.borderOf(context)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            canRequestFocus: false,
            onTap: onTap,
            borderRadius: borderRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    macro,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: AppColors.porchAmberOf(context),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
