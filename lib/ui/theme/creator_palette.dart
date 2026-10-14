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

import 'app_colors.dart';
import 'studio_colors.dart';

/// The colours a widget shared with the rest of the app needs when it is
/// drawn inside the AI Character Creator (docs/design/creator-ui-spec.md).
///
/// `CreatorTheme` puts [CreatorPalette.studio] on its theme. A shared widget
/// reads [maybeOf] and falls back to its own `AppColors` value when it is
/// null, so every screen outside the creator draws exactly as before. A
/// widget that lives in the creator but is also hosted elsewhere (the
/// Backend & Model step inside AI Enhance) reads [of], which falls back to
/// [CreatorPalette.app].
@immutable
class CreatorPalette extends ThemeExtension<CreatorPalette> {
  const CreatorPalette({
    required this.bg,
    required this.side,
    required this.card,
    required this.raise,
    required this.fieldFill,
    required this.fieldBorder,
    required this.line,
    required this.ink,
    required this.prose,
    required this.muted,
    required this.faint,
    required this.label,
    required this.iconAccent,
    required this.amber,
    required this.amberInk,
    required this.chipSelectedFill,
    required this.chipSelectedInk,
    required this.bad,
    required this.ok,
    required this.warn,
  });

  /// Page background.
  final Color bg;

  /// App bar, menus.
  final Color side;

  /// Cards and panels.
  final Color card;

  /// Chips, toggles, steer fields, upcoming step dots.
  final Color raise;

  /// Text field fill.
  final Color fieldFill;

  /// Text field border at rest.
  final Color fieldBorder;

  /// Borders and dividers.
  final Color line;

  /// Text.
  final Color ink;

  /// Secondary text, icon buttons.
  final Color prose;

  /// Subtitles, captions.
  final Color muted;

  /// Placeholders, counts.
  final Color faint;

  /// Labels above fields.
  final Color label;

  /// Small accent icons (the random-name dice).
  final Color iconAccent;

  /// Primary and outlined actions, switches.
  final Color amber;

  /// Text on an amber fill.
  final Color amberInk;

  /// A selected chip's fill.
  final Color chipSelectedFill;

  /// A selected chip's text.
  final Color chipSelectedInk;

  /// Stop, delete, errors.
  final Color bad;

  /// Ready / good status.
  final Color ok;

  /// Starting / loading status.
  final Color warn;

  /// The creator's palette, or null outside the creator.
  static CreatorPalette? maybeOf(BuildContext context) =>
      Theme.of(context).extension<CreatorPalette>();

  /// The creator's palette inside the creator; the app's colours elsewhere.
  static CreatorPalette of(BuildContext context) =>
      maybeOf(context) ?? CreatorPalette.app(context);

  /// The studio palette, per the spec's palette roles.
  factory CreatorPalette.studio(BuildContext context) => CreatorPalette(
    bg: StudioColors.bgOf(context),
    side: StudioColors.sideOf(context),
    card: StudioColors.cardOf(context),
    raise: StudioColors.raiseOf(context),
    fieldFill: StudioColors.bgOf(context),
    fieldBorder: StudioColors.lineOf(context),
    line: StudioColors.lineOf(context),
    ink: StudioColors.inkOf(context),
    prose: StudioColors.proseOf(context),
    muted: StudioColors.mutedOf(context),
    faint: StudioColors.faintOf(context),
    label: StudioColors.mutedOf(context),
    iconAccent: StudioColors.amberOf(context),
    amber: StudioColors.amberOf(context),
    amberInk: StudioColors.amberInkOf(context),
    chipSelectedFill: StudioColors.amberOf(context),
    chipSelectedInk: StudioColors.amberInkOf(context),
    bad: StudioColors.badOf(context),
    ok: StudioColors.tealOf(context),
    warn: StudioColors.honeyOf(context),
  );

  /// The app's own colours for the same roles, for creator widgets hosted
  /// outside the creator.
  factory CreatorPalette.app(BuildContext context) => CreatorPalette(
    bg: AppColors.backgroundOf(context),
    side: AppColors.surfaceOf(context),
    card: AppColors.cardOf(context),
    raise: AppColors.surfaceContainerOf(context),
    fieldFill: AppColors.surfaceContainerOf(context),
    fieldBorder: AppColors.borderOf(context),
    line: AppColors.borderOf(context),
    ink: AppColors.textPrimary(context),
    prose: AppColors.textSecondary(context),
    muted: AppColors.textTertiary(context),
    faint: AppColors.textTertiary(context),
    label: AppColors.textPrimary(context),
    iconAccent: AppColors.resolve(
      context,
      Colors.amberAccent,
      Colors.amber.shade700,
    ),
    amber: AppColors.porchAmberOf(context),
    amberInk: AppColors.onChaosAccent,
    chipSelectedFill: AppColors.porchAmberOf(context),
    chipSelectedInk: AppColors.resolve(context, Colors.white, Colors.black87),
    bad: AppColors.negativeAccentOf(context),
    ok: Colors.green.shade300,
    warn: Colors.orange.shade300,
  );

  /// The spec's field label: 11px / 600, 0.4px tracking. Callers pass the
  /// text upper-cased.
  TextStyle get labelStyle => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: label,
  );

  @override
  CreatorPalette copyWith({
    Color? bg,
    Color? side,
    Color? card,
    Color? raise,
    Color? fieldFill,
    Color? fieldBorder,
    Color? line,
    Color? ink,
    Color? prose,
    Color? muted,
    Color? faint,
    Color? label,
    Color? iconAccent,
    Color? amber,
    Color? amberInk,
    Color? chipSelectedFill,
    Color? chipSelectedInk,
    Color? bad,
    Color? ok,
    Color? warn,
  }) => CreatorPalette(
    bg: bg ?? this.bg,
    side: side ?? this.side,
    card: card ?? this.card,
    raise: raise ?? this.raise,
    fieldFill: fieldFill ?? this.fieldFill,
    fieldBorder: fieldBorder ?? this.fieldBorder,
    line: line ?? this.line,
    ink: ink ?? this.ink,
    prose: prose ?? this.prose,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    label: label ?? this.label,
    iconAccent: iconAccent ?? this.iconAccent,
    amber: amber ?? this.amber,
    amberInk: amberInk ?? this.amberInk,
    chipSelectedFill: chipSelectedFill ?? this.chipSelectedFill,
    chipSelectedInk: chipSelectedInk ?? this.chipSelectedInk,
    bad: bad ?? this.bad,
    ok: ok ?? this.ok,
    warn: warn ?? this.warn,
  );

  @override
  CreatorPalette lerp(CreatorPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return CreatorPalette(
      bg: mix(bg, other.bg),
      side: mix(side, other.side),
      card: mix(card, other.card),
      raise: mix(raise, other.raise),
      fieldFill: mix(fieldFill, other.fieldFill),
      fieldBorder: mix(fieldBorder, other.fieldBorder),
      line: mix(line, other.line),
      ink: mix(ink, other.ink),
      prose: mix(prose, other.prose),
      muted: mix(muted, other.muted),
      faint: mix(faint, other.faint),
      label: mix(label, other.label),
      iconAccent: mix(iconAccent, other.iconAccent),
      amber: mix(amber, other.amber),
      amberInk: mix(amberInk, other.amberInk),
      chipSelectedFill: mix(chipSelectedFill, other.chipSelectedFill),
      chipSelectedInk: mix(chipSelectedInk, other.chipSelectedInk),
      bad: mix(bad, other.bad),
      ok: mix(ok, other.ok),
      warn: mix(warn, other.warn),
    );
  }
}

/// `context.creatorPalette` reads [CreatorPalette.maybeOf]: the creator's
/// palette inside the AI Character Creator, null everywhere else.
extension CreatorPaletteLookup on BuildContext {
  CreatorPalette? get creatorPalette => CreatorPalette.maybeOf(this);
}
