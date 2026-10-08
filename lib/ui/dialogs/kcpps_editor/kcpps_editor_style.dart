// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The pieces the preset editor and the local model card are built from,
// sized and coloured as the approved sketch has them.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

TextStyle keText(
  BuildContext context, {
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? height,
  double? spacing,
}) => TextStyle(
  fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
  fontSize: size,
  fontWeight: weight,
  color: color ?? AppColors.slateInkOf(context),
  height: height,
  letterSpacing: spacing,
);

/// A small heading over a field.
class KeLabel extends StatelessWidget {
  const KeLabel(this.text, {super.key, this.size = 12});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: keText(
      context,
      size: size,
      weight: size == 12 ? FontWeight.w600 : FontWeight.w400,
      color: size == 12
          ? AppColors.slateFaintOf(context)
          : AppColors.slateMutedOf(context),
    ),
  );
}

/// One of the editor's sections: a titled card.
class KeSection extends StatelessWidget {
  const KeSection({
    super.key,
    required this.title,
    required this.children,
    this.gap = 14,
  });

  final String title;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
    decoration: BoxDecoration(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.hairlineOf(context, 0.10)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: keText(context, size: 15, weight: FontWeight.w600),
          ),
        ),
        for (final c in children) ...[SizedBox(height: gap), c],
      ],
    ),
  );
}

/// A row of buttons of which one is chosen.
class KeChoices<T> extends StatelessWidget {
  const KeChoices({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.height = 44,
    this.expand = true,
    this.enabled,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T> onSelected;
  final double height;
  final bool expand;

  /// Which choices can be picked; all when null.
  final bool Function(T value)? enabled;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      for (final v in values)
        _choice(context, v, v == selected, enabled?.call(v) ?? true),
    ];
    if (!expand) return Wrap(spacing: 6, runSpacing: 6, children: buttons);
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }

  Widget _choice(BuildContext context, T v, bool on, bool can) {
    final amber = AppColors.porchAmberOf(context);
    return Semantics(
      selected: on,
      button: true,
      child: Opacity(
        opacity: can ? 1 : 0.45,
        child: Material(
          color: on ? amber.withValues(alpha: 0.14) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: on ? amber : AppColors.hairlineOf(context, 0.12),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: can ? () => onSelected(v) : null,
            child: Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: expand ? null : 1,
                child: Text(
                  label(v),
                  style: keText(
                    context,
                    size: height == 44 ? 14 : 13,
                    color: on
                        ? AppColors.slateInkOf(context)
                        : AppColors.slateMutedOf(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A sunken text box: the name, a number.
class KeBox extends StatelessWidget {
  const KeBox({
    super.key,
    required this.controller,
    this.width,
    this.height = 40,
    this.number = false,
    this.error = false,
    this.fontSize = 14,
    this.semanticLabel,
    this.onChanged,
    this.keyName,
  });

  final TextEditingController controller;
  final double? width;
  final double height;
  final bool number;
  final bool error;
  final double fontSize;
  final String? semanticLabel;
  final ValueChanged<String>? onChanged;
  final String? keyName;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height == 44 ? 10 : 8);
    OutlineInputBorder edge(Color c, double w) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: c, width: w),
    );
    final red = AppColors.alertRedOf(context);
    return SizedBox(
      width: width,
      height: height,
      child: Semantics(
        label: semanticLabel,
        child: TextField(
          key: keyName == null ? null : ValueKey<String>(keyName!),
          controller: controller,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          inputFormatters: number
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          style: keText(context, size: fontSize),
          cursorColor: AppColors.porchAmberOf(context),
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.sunkenSurfaceOf(context),
            contentPadding: EdgeInsets.symmetric(
              horizontal: height == 44 ? 12 : 10,
              vertical: (height - fontSize * 1.4) / 2,
            ),
            enabledBorder: error
                ? edge(red, 2)
                : edge(AppColors.hairlineOf(context, 0.14), 1),
            focusedBorder: error
                ? edge(red, 2)
                : edge(AppColors.porchAmberOf(context), 1),
          ),
        ),
      ),
    );
  }
}

/// A checkbox with its words beside it. A [value] of null is the third
/// state, drawn as a dash: nothing was chosen. A tap from it answers "off".
class KeCheck extends StatelessWidget {
  const KeCheck({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool? value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      onTap: onChanged == null ? null : () => onChanged!(value == false),
      borderRadius: BorderRadius.circular(6),
      child: Opacity(
        opacity: onChanged == null ? 0.45 : 1,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                tristate: value == null,
                onChanged: onChanged == null
                    ? null
                    : (v) => onChanged!(v ?? false),
                activeColor: AppColors.porchAmberOf(context),
                checkColor: AppColors.onPorchAmber,
                side: BorderSide(color: AppColors.slateFaintOf(context)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: keText(
                  context,
                  size: 13,
                  color: AppColors.slateMutedOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

enum KeButtonKind { neutral, amberOutline, amber }

/// The editor's buttons: plain outline, amber outline, solid amber.
class KeButton extends StatelessWidget {
  const KeButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.kind = KeButtonKind.neutral,
    this.height = 44,
    this.padding = 16,
    this.fontSize = 14,
    this.expand = false,
    this.icon,
  });

  final String label;

  /// Shown instead of [label], which then only names the button.
  final IconData? icon;
  final VoidCallback? onPressed;
  final KeButtonKind kind;
  final double height;
  final double padding;
  final double fontSize;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final solid = kind == KeButtonKind.amber;
    final side = switch (kind) {
      KeButtonKind.neutral => AppColors.hairlineOf(context, 0.12),
      KeButtonKind.amberOutline => amber.withValues(alpha: 0.55),
      KeButtonKind.amber => Colors.transparent,
    };
    final fg = switch (kind) {
      KeButtonKind.neutral => AppColors.slateMutedOf(context),
      KeButtonKind.amberOutline => amber,
      KeButtonKind.amber => AppColors.onPorchAmber,
    };
    return Semantics(
      button: true,
      label: icon == null ? null : label,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Material(
          color: solid ? AppColors.porchAmber : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(height >= 44 ? 10 : 8),
            side: BorderSide(color: side),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(height >= 44 ? 10 : 8),
            onTap: onPressed,
            child: Container(
              height: height,
              width: expand ? double.infinity : null,
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Center(
                widthFactor: expand ? null : 1,
                child: icon != null
                    ? Icon(icon, size: fontSize, color: fg)
                    : Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: keText(
                          context,
                          size: fontSize,
                          color: fg,
                          weight: solid
                              ? FontWeight.w700
                              : kind == KeButtonKind.amberOutline
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small square or dot in a legend or a verdict, drawn rather than typed
/// so it looks the same in every font.
class KeMark extends StatelessWidget {
  const KeMark(this.color, {super.key, this.round = false, this.size = 10});

  final Color color;
  final bool round;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: round ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: round ? null : BorderRadius.circular(2),
    ),
  );
}

/// A fact about the model, as a rounded chip.
class KeChip extends StatelessWidget {
  const KeChip(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerOf(context),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text, style: keText(context, size: 12)),
  );
}
