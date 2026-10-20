// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_palette.dart';

/// Neutral ink that is not part of a palette: dims over content, faint
/// lines and wells that read on both dark and light grounds.
class InkColors {
  InkColors._();

  /// A darkening layer: modal dims, wells, scrims over pictures. Black in
  /// every theme, because it only has to push what is under it back.
  static Color dim(double alpha) => Colors.black.withValues(alpha: alpha);

  /// A darkening layer whose strength differs by mode.
  static Color dimOf(BuildContext context, double dark, double light) =>
      AppColors.resolve(context, dim(dark), dim(light));

  /// Drop shadows under raised cards and panels.
  static const Color shadow = Color(0x59000000);
  static const Color shadowDeep = Color(0x66000000);

  /// Text and icons laid over a picture, a dim or a gradient badge.
  static const Color onImage = Colors.white;

  /// The scrim behind a name laid over a portrait.
  static Color nameScrimOf(BuildContext context) =>
      AppColors.resolve(context, Colors.black87, Colors.black54);

  /// Secondary text. Dark mode keeps white at [alpha]; light mode uses the
  /// muted black that stays readable on paper.
  static Color mutedTextOf(BuildContext context, double alpha) =>
      AppColors.resolve(
        context,
        Colors.white.withValues(alpha: alpha),
        Colors.black54,
      );

  /// The faint fill behind a list row or card.
  static Color rowFillOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.white.withValues(alpha: 0.03),
    Colors.black.withValues(alpha: 0.02),
  );

  /// The border around a list row or card.
  static Color rowEdgeOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.white.withValues(alpha: 0.05),
    AppColors.borderOf(context),
  );

  /// The empty part of a progress bar or meter.
  static Color trackOf(BuildContext context, {double dark = 0.1}) =>
      AppColors.resolve(
        context,
        Colors.white.withValues(alpha: dark),
        AppColors.borderOf(context).withValues(alpha: 0.3),
      );

  /// A soft wash over a surface: white in dark, black in light.
  static Color washOf(BuildContext context, double dark, double light) =>
      AppColors.resolve(
        context,
        Colors.white.withValues(alpha: dark),
        Colors.black.withValues(alpha: light),
      );

  /// The border of a small text field.
  static Color fieldEdgeOf(BuildContext context) =>
      AppColors.resolve(context, Colors.white24, AppColors.borderOf(context));

  /// A disabled button's fill.
  static Color disabledFillOf(BuildContext context) =>
      AppColors.resolve(context, Colors.white10, Colors.black12);

  /// The raised panel of the first-run setup overlay.
  static Color panelOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFF1E1E26),
    AppColors.cardOf(context),
  );

  /// A frosted panel over a light dim, and its rim.
  static Color glassOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.white.withValues(alpha: 0.12),
    AppColors.cardOf(context),
  );
  static Color glassEdgeOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.white.withValues(alpha: 0.18),
    AppColors.borderOf(context),
  );

  /// The faint border around chip rows and pills.
  static Color faintLineOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.white10,
    Colors.black.withValues(alpha: 0.09),
  );

  /// The hairline border around tooltips and soft buttons.
  static Color lineOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.white12,
    Colors.black.withValues(alpha: 0.11),
  );

  /// The well behind a realism chip row. Light mode backs it with the card,
  /// because a chat theme can put a dark bubble under it in either mode and
  /// light-mode chip inks are deep tones. [dark] keeps each row's dim.
  static Color chipWellOf(
    BuildContext context, {
    Color dark = Colors.black12,
  }) => AppColors.resolve(context, dark, AppColors.cardOf(context));

  /// A drag grip on a resizable edge, or an empty avatar's fill.
  static Color gripOf(BuildContext context) =>
      AppColors.resolve(context, Colors.white24, Colors.black12);

  /// A drag handle bar.
  static Color handleOf(BuildContext context) =>
      AppColors.resolve(context, Colors.white38, Colors.black38);

  /// The outline of a soft home-screen button.
  static Color outlineOf(BuildContext context) =>
      AppColors.resolve(context, Colors.white24, Colors.black26);

  /// An unselected check circle on a card: its fill and its rim.
  static Color checkWellOf(BuildContext context) =>
      AppColors.resolve(context, Colors.black54, Colors.black12);
  static Color checkRimOf(BuildContext context) => handleOf(context);

  /// The border of a small chip or pill.
  static Color chipEdgeOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.white.withValues(alpha: 0.06),
    AppColors.borderOf(context).withValues(alpha: 0.6),
  );

  /// A sunken row in a list, such as a lorebook entry.
  static Color sunkenRowOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.white.withValues(alpha: 0.02),
    AppColors.surfaceContainerOf(context).withValues(alpha: 0.4),
  );

  /// A field set into a panel, such as the climate editor's inputs.
  static Color insetFieldOf(BuildContext context) =>
      AppColors.resolve(context, Colors.black26, Colors.white54);

  /// The caption strip and buttons laid over a picture, and their ink.
  static const Color imageScrim = Colors.black54;
  static const Color onImageMuted = Colors.white70;

  /// Faint labels and unset icons: a word count, an entry not yet embedded.
  static Color faintOf(BuildContext context) =>
      AppColors.resolve(context, Colors.white24, AppPalette.of(context).muted);

  /// The title of an empty list.
  static Color emptyTitleOf(BuildContext context) =>
      AppColors.resolve(context, Colors.white30, AppPalette.of(context).muted);

  /// The large glyph above an empty list.
  static Color ghostOf(BuildContext context) =>
      AppColors.resolve(context, Colors.white12, Colors.black12);

  /// A frosted welcome panel floating on the dim, and its rim.
  static Color frostPanelOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.white.withValues(alpha: 0.06),
    AppColors.cardOf(context),
  );
  static Color frostEdgeOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.white.withValues(alpha: 0.12),
    AppColors.borderOf(context),
  );
}
