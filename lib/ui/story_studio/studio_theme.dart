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
import 'package:google_fonts/google_fonts.dart';

import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The three type roles of the story spec (docs/design/porch-stories-ui-spec.md):
/// Figtree for UI, Literata for prose, JetBrains Mono for numbers. Each
/// carries a real fallback so an offline first launch still reads right.
class StudioType {
  StudioType._();

  static TextStyle ui(
    BuildContext context, {
    double size = 13.5,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
  }) => GoogleFonts.figtree(
    fontSize: size,
    fontWeight: weight,
    color: color ?? StudioColors.inkOf(context),
    height: height,
  ).copyWith(fontFamilyFallback: const ['SF Pro Text', 'Segoe UI', 'Roboto']);

  /// 11px uppercase label with 0.08em tracking.
  static TextStyle label(BuildContext context, {Color? color}) => ui(
    context,
    size: 11,
    weight: FontWeight.w500,
    color: color ?? StudioColors.mutedOf(context),
  ).copyWith(letterSpacing: 0.9);

  /// Beat text, interview quotes, bible fields: 14.5 / 1.7.
  static TextStyle prose(
    BuildContext context, {
    double size = 14.5,
    double height = 1.7,
    Color? color,
    FontStyle style = FontStyle.normal,
  }) => GoogleFonts.literata(
    fontSize: size,
    height: height,
    fontStyle: style,
    color: color ?? StudioColors.proseOf(context),
  ).copyWith(fontFamilyFallback: const ['Georgia', 'Times New Roman']);

  /// Scene labels ("3.3"), "from 3.3", times, token counts.
  static TextStyle mono(
    BuildContext context, {
    double size = 12,
    Color? color,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: size,
    color: color ?? StudioColors.mutedOf(context),
  ).copyWith(fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace']);
}

/// Wraps a story screen so every Material widget inside it (fields,
/// switches, menus, dialogs, scrollbars) renders in the studio palette
/// without per-widget colour code. The desktop twin of the `.studio` CSS
/// scope in web_ui/src/styles/studio.css.
class StudioTheme extends StatelessWidget {
  final Widget child;

  const StudioTheme({super.key, required this.child});

  static ThemeData of(BuildContext context) {
    final base = Theme.of(context);
    final ink = StudioColors.inkOf(context);
    final muted = StudioColors.mutedOf(context);
    final line = StudioColors.lineOf(context);
    final amber = StudioColors.amberOf(context);
    final card = StudioColors.cardOf(context);
    final bg = StudioColors.bgOf(context);
    final body = StudioType.ui(context);
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: c),
    );
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      cardColor: card,
      dividerColor: line,
      colorScheme: base.colorScheme.copyWith(
        primary: amber,
        onPrimary: StudioColors.amberInkOf(context),
        secondary: StudioColors.honeyOf(context),
        surface: card,
        onSurface: ink,
        outline: line,
        error: StudioColors.badOf(context),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
        fontFamily: body.fontFamily,
        fontFamilyFallback: body.fontFamilyFallback,
      ),
      iconTheme: IconThemeData(color: muted, size: 18),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bg,
        hintStyle: StudioType.ui(context, color: StudioColors.faintOf(context)),
        labelStyle: StudioType.ui(context, color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: border(line),
        enabledBorder: border(line),
        focusedBorder: border(amber),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? StudioColors.amberInkOf(context)
              : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? amber : line,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? amber : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(StudioColors.amberInkOf(context)),
        side: BorderSide(color: line, width: 2),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? amber : line,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: StudioColors.raiseOf(context),
        textStyle: body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: line),
        ),
        titleTextStyle: StudioType.ui(
          context,
          size: 15,
          weight: FontWeight.w700,
        ),
        contentTextStyle: StudioType.ui(context, size: 12.5, color: muted),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: StudioColors.raiseOf(context),
        contentTextStyle: body,
        actionTextColor: amber,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: line),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: StudioColors.raiseOf(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: line),
        ),
        textStyle: StudioType.ui(context, size: 12),
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
      listTileTheme: ListTileThemeData(textColor: ink, iconColor: muted),
      splashColor: amber.withValues(alpha: 0.08),
      highlightColor: amber.withValues(alpha: 0.06),
      hoverColor: amber.withValues(alpha: 0.05),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: of(context),
    child: DefaultTextStyle.merge(style: StudioType.ui(context), child: child),
  );
}
