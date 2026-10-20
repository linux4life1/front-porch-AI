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
//
// Manual creator: the shared field label, decoration and editors the steps
// build their forms from.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

class CreatorInputLabel extends StatelessWidget {
  const CreatorInputLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (required)
          Text(' *', style: TextStyle(color: StatusColors.dangerOf(context))),
      ],
    );
  }
}

InputDecoration creatorInputDecoration(BuildContext context, String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textTertiary(context), fontSize: 14),
    filled: true,
    fillColor: AppColors.surfaceContainerOf(context),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.borderOf(context)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.borderOf(context)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.porchAmberOf(context)),
    ),
    contentPadding: const EdgeInsets.all(14),
  );
}

/// Labelled multi-line editor with an "Expand editor" button.
class CreatorExpandableField extends StatelessWidget {
  const CreatorExpandableField(
    this.label,
    this.controller, {
    super.key,
    this.hint = '',
    this.maxLines = 3,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CreatorInputLabel(label),
            const Spacer(),
            IconButton(
              onPressed: () => showExpandedEditorDialog(
                context: context,
                title: label,
                controller: controller,
              ),
              icon: Icon(
                Icons.open_in_full,
                size: 16,
                color: AppColors.textTertiary(context),
              ),
              tooltip: 'Expand editor',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: 14,
            height: 1.5,
          ),
          spellCheckConfiguration: AppTextField.platformSpellCheck(),
          decoration: creatorInputDecoration(context, hint),
        ),
      ],
    );
  }
}

/// The Review step's compact editor for one already-written field.
class CreatorReviewField extends StatelessWidget {
  const CreatorReviewField(
    this.label,
    this.controller, {
    super.key,
    this.maxLines = 3,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.formAccentOf(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          AppTextField(
            controller: controller,
            maxLines: maxLines,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
              height: 1.5,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.formAccentOf(context)),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }
}

/// The centred, scrolling, 700-wide column every form step sits in.
class CreatorStepFrame extends StatelessWidget {
  const CreatorStepFrame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A step's 28pt heading.
class CreatorStepTitle extends StatelessWidget {
  const CreatorStepTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary(context),
      ),
    );
  }
}

/// A step's secondary-coloured lead paragraph.
class CreatorStepLead extends StatelessWidget {
  const CreatorStepLead(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        color: AppColors.textSecondary(context),
        height: 1.5,
      ),
    );
  }
}
