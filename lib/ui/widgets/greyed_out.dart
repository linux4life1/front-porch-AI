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

/// A control that is present but cannot be used here, at reduced opacity.
/// Hover (pointer) or long-press (touch) says why in [tooltip]; it takes no
/// taps and no keyboard focus, and reads to a screen reader as disabled.
class GreyedOut extends StatelessWidget {
  const GreyedOut({super.key, required this.tooltip, required this.child});

  final String tooltip;
  final Widget child;

  /// How faded a greyed control is.
  static const opacity = 0.45;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        enabled: false,
        child: Opacity(
          opacity: opacity,
          child: ExcludeFocus(child: AbsorbPointer(child: child)),
        ),
      ),
    );
  }
}
