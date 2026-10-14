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

import 'package:front_porch_ai/ui/theme/creator_palette.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Wraps the AI Character Creator so every Material widget inside it
/// (fields, switches, sliders, menus, dialogs, the shared Realism and Needs
/// forms) follows the studio palette (docs/design/creator-ui-spec.md).
///
/// The palette matches the Porch Stories `StudioTheme`; the type does not.
/// The creator stays on the app's system font, so this theme sets colours,
/// sizes and shapes only and never names a font family (`StudioTheme.of`
/// builds Figtree styles, which would also start a font download).
class CreatorTheme extends StatelessWidget {
  const CreatorTheme({super.key, required this.child});

  final Widget child;

  static ThemeData of(BuildContext context) {
    final base = Theme.of(context);
    final ink = StudioColors.inkOf(context);
    final prose = StudioColors.proseOf(context);
    final muted = StudioColors.mutedOf(context);
    final line = StudioColors.lineOf(context);
    final amber = StudioColors.amberOf(context);
    final amberInk = StudioColors.amberInkOf(context);
    final card = StudioColors.cardOf(context);
    final bg = StudioColors.bgOf(context);
    final side = StudioColors.sideOf(context);
    final raise = StudioColors.raiseOf(context);
    // Every style below starts from the app's body style, so it keeps the
    // app's font (a bare TextStyle would drop the family).
    final body = base.textTheme.bodyMedium ?? const TextStyle();
    RoundedRectangleBorder rounded(double r) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(r),
      side: BorderSide(color: line),
    );
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      cardColor: card,
      dividerColor: line,
      colorScheme: base.colorScheme.copyWith(
        primary: amber,
        onPrimary: amberInk,
        secondary: StudioColors.honeyOf(context),
        surface: card,
        onSurface: ink,
        onSurfaceVariant: muted,
        surfaceContainerHighest: raise,
        outline: line,
        outlineVariant: line,
        error: StudioColors.badOf(context),
      ),
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      iconTheme: IconThemeData(color: prose),
      // Only `border` is set: the decorator colours its side from the
      // scheme (line at rest, amber on focus), and a field that asks for no
      // border (the steer fields) keeps none.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: bg,
        hintStyle: body.copyWith(
          fontSize: 14,
          color: StudioColors.faintOf(context),
        ),
        labelStyle: body.copyWith(color: muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? amberInk : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? amber : line,
        ),
        trackOutlineColor: WidgetStatePropertyAll(line.withValues(alpha: 0)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? amber : bg,
        ),
        checkColor: WidgetStatePropertyAll(amberInk),
        side: BorderSide(color: line, width: 2),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? amber : line,
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: amber,
        inactiveTrackColor: line,
        thumbColor: amber,
        overlayColor: amber.withValues(alpha: 0.12),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: raise,
        selectedColor: amber,
        side: BorderSide.none,
        labelStyle: body.copyWith(fontSize: 13, color: ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: side,
        textStyle: body.copyWith(fontSize: 14, color: ink),
        shape: rounded(10),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: card,
        shape: rounded(20),
        titleTextStyle: body.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        contentTextStyle: body.copyWith(
          fontSize: 14,
          height: 1.5,
          color: prose,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: raise,
        contentTextStyle: body.copyWith(color: ink),
        actionTextColor: amber,
        behavior: SnackBarBehavior.floating,
        shape: rounded(8),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: raise,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: line),
        ),
        textStyle: body.copyWith(fontSize: 12, color: ink),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: amber,
        linearTrackColor: line,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: amber,
        selectionColor: amber.withValues(alpha: 0.3),
        selectionHandleColor: amber,
      ),
      listTileTheme: ListTileThemeData(textColor: ink, iconColor: prose),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: side,
        foregroundColor: ink,
        surfaceTintColor: side,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      // Shared widgets read this to draw in the creator's palette.
      extensions: [
        ...base.extensions.values.where((e) => e is! CreatorPalette),
        CreatorPalette.studio(context),
      ],
      splashColor: amber.withValues(alpha: 0.08),
      highlightColor: amber.withValues(alpha: 0.06),
      hoverColor: amber.withValues(alpha: 0.05),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: of(context),
    child: DefaultTextStyle.merge(
      style: TextStyle(color: StudioColors.inkOf(context)),
      child: child,
    ),
  );
}
