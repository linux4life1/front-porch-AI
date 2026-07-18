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
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Compatibility-aware LoRA picker for the Image Studio.
///
/// Given the LoRAs (already tagged with a base-model family by the service) and
/// the active checkpoint's family, it applies the confidence-driven policy:
///   • Compatible + unknown + name-only "likely" mismatches stay in the picker,
///     each badged with its family.
///   • Metadata-confirmed ("certain") mismatches are tucked behind a
///     "Show N incompatible" drawer — they will break, so they are hidden by
///     default but one tap away.
///   • Whenever the *selected* LoRA is any kind of mismatch, an inline warning
///     banner appears — so even a LoRA pulled out of the drawer on purpose is
///     flagged before generating.
///
/// Renders the picker, the optional drawer, the warning banner, and the weight
/// slider. The parent owns the "LoRA" heading and helper line.
class LoraPicker extends StatefulWidget {
  final List<LoraOption> loras;
  final ModelFamily checkpointFamily;
  final String selected;
  final double weight;
  final ValueChanged<String> onSelected;
  final ValueChanged<double> onWeightChanged;

  const LoraPicker({
    super.key,
    required this.loras,
    required this.checkpointFamily,
    required this.selected,
    required this.weight,
    required this.onSelected,
    required this.onWeightChanged,
  });

  @override
  State<LoraPicker> createState() => _LoraPickerState();
}

class _LoraPickerState extends State<LoraPicker> {
  bool _drawerOpen = false;
  double? _dragWeight;

  LoraCompat _compat(LoraOption l) => ImageModelFamily.compatibility(
    l.family,
    widget.checkpointFamily,
    metadataBacked: l.familyFromMetadata,
  );

  // Family badge, colored by the verdict (not just the family) so the eye reads
  // safe/likely/certain at a glance. Sixth-tone warm-porch semantics.
  Color _okColor(BuildContext c) => AppColors.resolve(c, const Color(0xFF9BBB7C), const Color(0xFF5E7E4A));
  Color _warnColor(BuildContext c) => AppColors.resolve(c, const Color(0xFFDAA83F), const Color(0xFFA97514));
  Color _badColor(BuildContext c) => AppColors.resolve(c, const Color(0xFFD6795D), const Color(0xFFA94E36));

  Widget _badge(BuildContext c, LoraOption l, LoraCompat compat) {
    final Color fg;
    final String text;
    switch (compat) {
      case LoraCompat.match:
        fg = _okColor(c);
        text = '${l.family.label} ✓';
        break;
      case LoraCompat.likely:
        fg = _warnColor(c);
        text = '${l.family.label} · likely';
        break;
      case LoraCompat.certain:
        fg = _badColor(c);
        text = l.family.label;
        break;
      case LoraCompat.unknown:
        fg = AppColors.textTertiary(c);
        text = l.family == ModelFamily.unknown ? 'unlabeled' : l.family.label;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 8.5, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _row(BuildContext c, LoraOption l, LoraCompat compat) => Row(
    children: [
      Expanded(
        child: Text(
          l.name,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textPrimary(c), fontSize: 10),
        ),
      ),
      if (widget.checkpointFamily != ModelFamily.unknown &&
          l.family != ModelFamily.unknown) ...[
        const SizedBox(width: 6),
        _badge(c, l, compat),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    // Partition by verdict. Visible = everything except metadata-certain
    // mismatches; those go in the drawer. Sort visible: matches, then unknowns,
    // then "likely" nudges.
    final visible = <LoraOption>[];
    final hidden = <LoraOption>[];
    for (final l in widget.loras) {
      if (_compat(l) == LoraCompat.certain) {
        hidden.add(l);
      } else {
        visible.add(l);
      }
    }
    int rank(LoraOption l) {
      switch (_compat(l)) {
        case LoraCompat.match:
          return 0;
        case LoraCompat.unknown:
          return 1;
        case LoraCompat.likely:
          return 2;
        case LoraCompat.certain:
          return 3;
      }
    }

    visible.sort((a, b) => rank(a).compareTo(rank(b)));

    // The dropdown must contain the current value even if it is a hidden
    // (certain-incompatible) LoRA the user deliberately kept selected.
    final selectedOpt = _selectedOption();
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: '',
        child: Text(
          '— None —',
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 10),
        ),
      ),
      for (final l in visible)
        DropdownMenuItem(value: l.name, child: _row(context, l, _compat(l))),
      if (selectedOpt != null && _compat(selectedOpt) == LoraCompat.certain)
        DropdownMenuItem(
          value: selectedOpt.name,
          child: _row(context, selectedOpt, LoraCompat.certain),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _dropdownValue(items),
          dropdownColor: AppColors.surfaceContainerOf(context),
          isExpanded: true,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 10),
          decoration: InputDecoration(
            hintText: widget.loras.isEmpty ? 'Available when connected' : 'LoRA (opt)',
            hintStyle: TextStyle(color: AppColors.textTertiary(context)),
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          items: items,
          onChanged: (val) {
            if (val != null) widget.onSelected(val);
          },
        ),

        // "Show N incompatible" drawer for metadata-confirmed mismatches.
        if (hidden.isNotEmpty) _buildDrawer(context, hidden),

        // Inline warning whenever the selected LoRA is any kind of mismatch.
        if (selectedOpt != null) _buildBanner(context, selectedOpt),

        // Weight slider (only when a LoRA is selected).
        if (widget.selected.isNotEmpty) _buildWeight(context),
      ],
    );
  }

  LoraOption? _selectedOption() {
    if (widget.selected.isEmpty) return null;
    for (final l in widget.loras) {
      if (l.name == widget.selected) return l;
    }
    return null;
  }

  // Guard the DropdownButtonFormField value so it always matches an item (Flutter
  // asserts otherwise): fall back to null when the persisted name is absent.
  String? _dropdownValue(List<DropdownMenuItem<String>> items) {
    if (widget.selected.isEmpty) return '';
    return items.any((i) => i.value == widget.selected) ? widget.selected : null;
  }

  Widget _buildDrawer(BuildContext context, List<LoraOption> hidden) {
    final families = <String>{for (final l in hidden) l.family.label}.join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _drawerOpen,
          onExpansionChanged: (v) => setState(() => _drawerOpen = v),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(left: 4, bottom: 4),
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(
            'Show ${hidden.length} incompatible ($families)',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            for (final l in hidden)
              InkWell(
                onTap: () => widget.onSelected(l.name),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
                  child: _row(context, l, LoraCompat.certain),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner(BuildContext context, LoraOption sel) {
    final compat = _compat(sel);
    if (compat == LoraCompat.match || compat == LoraCompat.unknown) {
      return const SizedBox.shrink();
    }
    final certain = compat == LoraCompat.certain;
    final color = certain ? _badColor(context) : _warnColor(context);
    final ckpt = widget.checkpointFamily.label;
    final msg = certain
        ? 'This is an ${sel.family.label} LoRA but your checkpoint is $ckpt — different architectures, so the result will be noise or fail. Pick a $ckpt LoRA.'
        : 'This looks like an ${sel.family.label} LoRA and your checkpoint is $ckpt. It may not apply cleanly — double-check the result.';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(certain ? Icons.error_outline : Icons.warning_amber_rounded, size: 13, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(color: AppColors.textPrimary(context), fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeight(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Text(
          'Wt',
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 9),
        ),
        Expanded(
          child: Slider(
            value: _dragWeight ?? widget.weight,
            min: 0,
            max: 1,
            divisions: 20,
            activeColor: AppColors.formMasterAccent,
            onChanged: (v) => setState(() => _dragWeight = v),
            onChangeEnd: (v) {
              setState(() => _dragWeight = null);
              widget.onWeightChanged(v);
            },
          ),
        ),
        SizedBox(
          width: 24,
          child: Text(
            (_dragWeight ?? widget.weight).toStringAsFixed(2),
            style: const TextStyle(fontSize: 8),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    ),
  );
}
