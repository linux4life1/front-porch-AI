// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop Report control + dialog. Extracted from stoop_card_detail_page.dart
// so that file does not grow, and so unverified accounts never open Report.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Report / confirm-email / hidden. Unverified users get a nudge, not a dialog.
class StoopReportControl extends StatelessWidget {
  final BackporchUser? user;
  final VoidCallback onReport;
  const StoopReportControl({
    super.key,
    required this.user,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    if (user == null) return const SizedBox.shrink();
    if (!stoopCanReport(user)) {
      final ember = stoopEmberText(context);
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Confirm your email to report. Check your inbox, or resend from Account.',
                ),
              ),
            );
          },
          style: TextButton.styleFrom(
            foregroundColor: ember,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: const Text('Confirm email to report'),
        ),
      );
    }
    final ember = stoopEmberText(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onReport,
        icon: const Icon(Icons.flag_rounded, size: 18),
        label: const Text('Report Character'),
        style: TextButton.styleFrom(
          foregroundColor: ember,
          backgroundColor: AppColors.stoopEmber.withValues(alpha: 0.1),
          side: BorderSide(color: AppColors.stoopEmber.withValues(alpha: 0.45)),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
    );
  }
}

/// Category + required written reason. Empty reason keeps the dialog open.
class StoopReportDialog extends StatefulWidget {
  final String title;
  const StoopReportDialog({super.key, this.title = 'Report this card'});

  @override
  State<StoopReportDialog> createState() => _StoopReportDialogState();
}

class _StoopReportDialogState extends State<StoopReportDialog> {
  static const _categories = {
    'ILLEGAL': 'Illegal / involves minors',
    'PROHIBITED_IMAGE': 'Nude / explicit image (not allowed)',
    'MISLABELED': 'Wrong or missing NSFW label',
    'STOLEN': 'Stolen / reuploaded',
    'LOW_EFFORT': 'Low-effort / slop',
    'SPAM': 'Spam or broken',
    'OTHER': 'Something else',
  };
  String _category = 'ILLEGAL';
  final _reason = TextEditingController();
  String? _hint;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _reason.text.trim();
    if (!stoopReportReasonOk(text)) {
      setState(() => _hint = 'Please add a reason.');
      return;
    }
    Navigator.pop(context, (category: _category, reason: text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: stoopCard2(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: stoopBorderHi(context)),
      ),
      title: Text(widget.title, style: stoopDisplay(context, size: 19)),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioGroup<String>(
            groupValue: _category,
            onChanged: (v) => setState(() => _category = v ?? _category),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in _categories.entries)
                  RadioListTile<String>(
                    value: e.key,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: AppColors.stoopAmber,
                    title: Text(
                      e.value,
                      style: TextStyle(color: stoopCream2(context)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLines: 2,
            maxLength: 500,
            style: TextStyle(color: stoopCream(context)),
            decoration: stoopInput(context, 'What’s wrong? (required)'),
            onChanged: (_) {
              if (_hint != null) setState(() => _hint = null);
            },
          ),
          if (_hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _hint!,
                style: TextStyle(color: stoopEmberText(context), fontSize: 13),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: stoopMute(context)),
          child: const Text('Cancel'),
        ),
        StoopAmberButton(
          label: 'Submit report',
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          onPressed: _submit,
        ),
      ],
    );
  }
}
