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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

// Per-field review cards for the AI Enhance Review step (before/after,
// greetings, lorebook) — the pieces EnhanceReviewBody composes.

/// The bordered card every review section sits in.
class EnhanceReviewSectionCard extends StatelessWidget {
  const EnhanceReviewSectionCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: child,
    );
  }
}

/// Section title with its "Use this" switch.
class EnhanceReviewSectionHeader extends StatelessWidget {
  const EnhanceReviewSectionHeader({
    super.key,
    required this.title,
    required this.use,
    required this.onUseChanged,
  });

  final String title;
  final bool use;
  final ValueChanged<bool> onUseChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
        ),
        Text(
          'Use this',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
        Switch(
          value: use,
          activeThumbColor: AppColors.porchAmberOf(context),
          onChanged: onUseChanged,
        ),
      ],
    );
  }
}

/// The original text, read-only, in a short scrolling box.
class EnhanceReviewOldText extends StatelessWidget {
  const EnhanceReviewOldText({
    super.key,
    required this.label,
    required this.text,
  });

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 140),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: Text(
              text.isEmpty ? '(empty)' : text,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The rewritten text, editable; greyed out while its section is unused.
class EnhanceReviewNewField extends StatelessWidget {
  const EnhanceReviewNewField({
    super.key,
    required this.label,
    required this.controller,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.porchAmberOf(context),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: null,
          minLines: 2,
          style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context)),
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
              borderSide: BorderSide(color: AppColors.porchAmberOf(context)),
            ),
            contentPadding: const EdgeInsets.all(8),
          ),
        ),
      ],
    );
  }
}

/// One rewritten text field: header + switch, Before, and editable After.
class EnhanceReviewFieldSection extends StatelessWidget {
  const EnhanceReviewFieldSection({
    super.key,
    required this.title,
    required this.use,
    required this.onUseChanged,
    required this.oldValue,
    required this.controller,
  });

  final String title;
  final bool use;
  final ValueChanged<bool> onUseChanged;
  final String oldValue;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return EnhanceReviewSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnhanceReviewSectionHeader(
            title: title,
            use: use,
            onUseChanged: onUseChanged,
          ),
          const SizedBox(height: 8),
          EnhanceReviewOldText(label: 'Before', text: oldValue),
          const SizedBox(height: 8),
          EnhanceReviewNewField(
            label: 'After (editable)',
            controller: controller,
            enabled: use,
          ),
        ],
      ),
    );
  }
}

/// First message + alternates: the original first message, then every
/// rewritten greeting editable under one switch.
class EnhanceReviewGreetingsSection extends StatelessWidget {
  const EnhanceReviewGreetingsSection({
    super.key,
    required this.use,
    required this.onUseChanged,
    required this.originalFirstMessage,
    required this.firstMessageController,
    required this.altControllers,
  });

  final bool use;
  final ValueChanged<bool> onUseChanged;
  final String originalFirstMessage;
  final TextEditingController firstMessageController;
  final List<TextEditingController> altControllers;

  @override
  Widget build(BuildContext context) {
    return EnhanceReviewSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnhanceReviewSectionHeader(
            title: 'First message + alternates',
            use: use,
            onUseChanged: onUseChanged,
          ),
          const SizedBox(height: 8),
          EnhanceReviewOldText(
            label: 'Before (first message)',
            text: originalFirstMessage,
          ),
          const SizedBox(height: 8),
          EnhanceReviewNewField(
            label: 'After (editable)',
            controller: firstMessageController,
            enabled: use,
          ),
          for (var i = 0; i < altControllers.length; i++) ...[
            const SizedBox(height: 8),
            EnhanceReviewNewField(
              label: 'Alternate ${i + 1} (editable)',
              controller: altControllers[i],
              enabled: use,
            ),
          ],
        ],
      ),
    );
  }
}

/// The proposed lorebook entries, each with its own keep checkbox.
class EnhanceReviewLorebookSection extends StatelessWidget {
  const EnhanceReviewLorebookSection({
    super.key,
    required this.entries,
    required this.useEntry,
    required this.onUseEntryChanged,
  });

  final List<LorebookEntry> entries;
  final List<bool> useEntry;
  final void Function(int index, bool use) onUseEntryChanged;

  @override
  Widget build(BuildContext context) {
    return EnhanceReviewSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New lorebook entries',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < entries.length; i++)
            CheckboxListTile(
              value: useEntry[i],
              onChanged: (v) => onUseEntryChanged(i, v ?? false),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.porchAmberOf(context),
              checkColor: AppColors.onAccentOf(context),
              contentPadding: EdgeInsets.zero,
              title: Text(
                entries[i].name,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary(context),
                ),
              ),
              subtitle: Text(
                entries[i].content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
