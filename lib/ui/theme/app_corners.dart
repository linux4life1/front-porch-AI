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

import 'appearance_options.dart';

/// The corner-roundness choice, installed on [ThemeData] so hand-drawn
/// cards, bubbles and dialogs scale their radii with the Material ones.
@immutable
class AppCorners extends ThemeExtension<AppCorners> {
  const AppCorners(this.corners);

  final UiCorners corners;

  static const AppCorners standard = AppCorners(UiCorners.standard);

  static AppCorners of(BuildContext context) =>
      Theme.of(context).extension<AppCorners>() ?? standard;

  /// [base] (today's radius at Default) scaled by the user's choice.
  double scaled(double base) => base * corners.scale;

  /// A uniform [BorderRadius] of [base], scaled.
  BorderRadius circular(double base) => BorderRadius.circular(scaled(base));

  @override
  AppCorners copyWith({UiCorners? corners}) =>
      AppCorners(corners ?? this.corners);

  @override
  AppCorners lerp(AppCorners? other, double t) =>
      t < 0.5 ? this : (other ?? this);

  @override
  bool operator ==(Object other) =>
      other is AppCorners && other.corners == corners;

  @override
  int get hashCode => corners.hashCode;
}
