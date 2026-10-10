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
import 'package:flutter/services.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Shared greet / regenerated-swipe picker. Tapping a card pops with that
/// variant's index (commit-once — the caller applies it).
Future<int?> showVariantPickerDialog(
  BuildContext context, {
  required String title,
  required List<VariantOption> variants,
}) {
  final size = MediaQuery.sizeOf(context);
  final width = (size.width - 40).clamp(320.0, 680.0);
  final height = (size.height * 0.72).clamp(280.0, 620.0);
  return showWarmDialog<int>(
    context,
    title: title,
    accent: AppColors.porchAmberOf(context),
    width: width,
    content: SizedBox(
      width: width,
      height: height,
      child: _VariantPickerBody(variants: variants),
    ),
    actions: [warmDialogCancel(context, label: 'Close')],
  );
}

class _VariantPickerBody extends StatefulWidget {
  const _VariantPickerBody({required this.variants});

  final List<VariantOption> variants;

  @override
  State<_VariantPickerBody> createState() => _VariantPickerBodyState();
}

class _VariantPickerBodyState extends State<_VariantPickerBody> {
  late final TextEditingController _jump;
  int? _expanded;

  @override
  void initState() {
    super.initState();
    final current = widget.variants.where((v) => v.isCurrent);
    _jump = TextEditingController(
      text: current.isEmpty ? '1' : '${current.first.index + 1}',
    );
  }

  @override
  void dispose() {
    _jump.dispose();
    super.dispose();
  }

  void _go() {
    final n = int.tryParse(_jump.text.trim());
    if (n == null) return;
    final last = widget.variants.length;
    if (last == 0) return;
    final index = n.clamp(1, last) - 1;
    Navigator.pop(context, index);
  }

  @override
  Widget build(BuildContext context) {
    final variants = widget.variants;
    if (variants.isEmpty) {
      return Center(
        child: Text(
          'No variants.',
          style: TextStyle(color: AppColors.textTertiary(context)),
        ),
      );
    }
    final greet = variants.first.kind == VariantKind.greet;
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: variants.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final v = variants[i];
              return _VariantCard(
                variant: v,
                expanded: _expanded == v.index,
                onToggleExpand: () => setState(() {
                  _expanded = _expanded == v.index ? null : v.index;
                }),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              greet ? 'Greet #' : 'Swipe #',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: TextField(
                key: const Key('variant-jump-field'),
                controller: _jump,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _go(),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary(context),
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
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
                    borderSide: BorderSide(
                      color: AppColors.porchAmberOf(context),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('variant-jump-go'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.porchAmberOf(context),
                foregroundColor: AppColors.onChaosAccent,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: _go,
              child: const Text('Go'),
            ),
          ],
        ),
      ],
    );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({
    required this.variant,
    required this.expanded,
    required this.onToggleExpand,
  });

  final VariantOption variant;
  final bool expanded;
  final VoidCallback onToggleExpand;

  Future<void> _copy() async {
    final body = variant.text.isEmpty ? variant.snippet : variant.text;
    await Clipboard.setData(ClipboardData(text: body));
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    final preview = variant.text.isEmpty
        ? (variant.snippet.isEmpty ? '(empty)' : variant.snippet)
        : variant.text;
    return Material(
      key: Key('variant-card-${variant.index}'),
      color: variant.isCurrent
          ? accent.withValues(alpha: 0.16)
          : AppColors.surfaceContainerOf(context).withValues(alpha: 0.65),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: variant.isCurrent
              ? accent.withValues(alpha: 0.75)
              : AppColors.borderOf(context).withValues(alpha: 0.7),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.pop(context, variant.index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${variant.index + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  if (variant.isCurrent) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Current',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onChaosAccent,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${variant.label} · '
                      '${variant.charCount} characters · '
                      '${variant.tokenCount}t',
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  ),
                  IconButton(
                    key: Key('variant-expand-${variant.index}'),
                    tooltip: expanded ? 'Collapse' : 'Expand',
                    icon: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    color: AppColors.iconSecondary(context),
                    onPressed: onToggleExpand,
                  ),
                  IconButton(
                    key: Key('variant-copy-${variant.index}'),
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy_outlined),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    color: AppColors.iconSecondary(context),
                    onPressed: _copy,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                preview,
                maxLines: expanded ? null : 3,
                overflow: expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
