// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Fullscreen message editor for chat. Replaces the old cramped AlertDialog:
// RP syntax highlighting via StyledTextController, thinking content edited in
// its own section (no raw <think> tags), keyboard shortcuts, dirty discard
// confirm, and a character count.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/ui/widgets/styled_text_controller.dart';
import 'package:front_porch_ai/utils/think_tags.dart';

/// Opens the fullscreen message editor. Returns the joined text on save, or
/// `null` if the user cancelled.
Future<String?> showMessageEditDialog({
  required BuildContext context,
  required String initialText,
  String title = 'Edit Message',
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _MessageEditDialog(
      initialText: initialText,
      title: title,
    ),
  );
}

class _MessageEditDialog extends StatefulWidget {
  final String initialText;
  final String title;

  const _MessageEditDialog({
    required this.initialText,
    required this.title,
  });

  @override
  State<_MessageEditDialog> createState() => _MessageEditDialogState();
}

class _MessageEditDialogState extends State<_MessageEditDialog> {
  late final StyledTextController _bodyController;
  late final TextEditingController _thinkingController;
  late final String _initialThinking;
  late final String _initialBody;
  late bool _thinkingExpanded;

  @override
  void initState() {
    super.initState();
    final parts = splitMessageForEdit(widget.initialText);
    _initialThinking = parts.thinking;
    _initialBody = parts.body;
    _thinkingExpanded = parts.thinking.isNotEmpty;
    _bodyController = StyledTextController(
      text: parts.body,
      preset: StyledTextPreset.prose,
    );
    _thinkingController = TextEditingController(text: parts.thinking);
    _bodyController.addListener(_onChanged);
    _thinkingController.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _isDirty {
    return _bodyController.text != _initialBody ||
        _thinkingController.text.trim() != _initialThinking;
  }

  String get _joined => joinMessageEdit(
        thinking: _thinkingController.text,
        body: _bodyController.text,
      );

  int get _charCount => _joined.length;

  Future<void> _cancel() async {
    if (_isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceOf(ctx),
          title: Text(
            'Discard changes?',
            style: TextStyle(color: AppColors.textPrimary(ctx)),
          ),
          content: Text(
            'You have unsaved edits to this message.',
            style: TextStyle(color: AppColors.textSecondary(ctx)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Keep editing',
                style: TextStyle(color: AppColors.textSecondary(ctx)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Discard',
                style: TextStyle(color: AppColors.bondNegOf(ctx)),
              ),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  void _save() {
    Navigator.pop(context, _joined);
  }

  @override
  void dispose() {
    _bodyController.removeListener(_onChanged);
    _thinkingController.removeListener(_onChanged);
    _bodyController.dispose();
    _thinkingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final saveChord = isMac ? '⌘↵' : 'Ctrl+Enter';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        SingleActivator(
          LogicalKeyboardKey.enter,
          meta: isMac,
          control: !isMac,
        ): _save,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(16),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          backgroundColor: AppColors.surfaceOf(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                Divider(height: 1, color: AppColors.borderOf(context)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildThinkingSection(context),
                        const SizedBox(height: 8),
                        Text(
                          'Message',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(child: _buildBodyField(context)),
                      ],
                    ),
                  ),
                ),
                _buildFooter(context, saveChord),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.edit_note,
            color: AppColors.textSecondary(context),
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _cancel,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textTertiary(context),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.formMasterAccent,
              foregroundColor: AppColors.onChaosAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _thinkingExpanded = !_thinkingExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _thinkingExpanded
                      ? Icons.expand_more
                      : Icons.chevron_right,
                  size: 18,
                  color: AppColors.textSecondary(context),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.psychology_outlined,
                  size: 16,
                  color: AppColors.textSecondary(context),
                ),
                const SizedBox(width: 6),
                Text(
                  'Thinking',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                if (_thinkingController.text.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.formMasterAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_thinkingController.text.trim().length} chars',
                      style: TextStyle(
                        color: AppColors.formMasterAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  _thinkingExpanded
                      ? 'Hide model reasoning'
                      : 'Edit model reasoning (no tags needed)',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_thinkingExpanded) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 140,
            child: AppTextField(
              controller: _thinkingController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
              decoration: InputDecoration(
                hoverColor: Colors.transparent,
                hintText: 'Model reasoning / chain-of-thought…',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontStyle: FontStyle.italic,
                ),
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.formMasterAccent.withValues(alpha: 0.5),
                  ),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBodyField(BuildContext context) {
    return AppTextField(
      controller: _bodyController,
      maxLines: null,
      expands: true,
      autofocus: true,
      textAlignVertical: TextAlignVertical.top,
      style: TextStyle(
        color: AppColors.textPrimary(context),
        fontSize: 15,
        height: 1.55,
      ),
      decoration: InputDecoration(
        hoverColor: Colors.transparent,
        hintText: 'Message text…  "dialogue" and *actions* are highlighted',
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.formMasterAccent),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, String saveChord) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.borderOf(context)),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$_charCount characters',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
          if (_isDirty) ...[
            const SizedBox(width: 10),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.formMasterAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Unsaved',
              style: TextStyle(
                color: AppColors.formMasterAccent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const Spacer(),
          Text(
            'Esc cancel  ·  $saveChord save',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
