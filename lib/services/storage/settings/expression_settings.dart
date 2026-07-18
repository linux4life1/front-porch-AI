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

import 'settings_base.dart';

/// Expression images / avatar classification + display settings.
///
/// Lifted Stage 7.
class ExpressionSettings with SettingsBase {
  bool _expressionEnabled = false;
  String _expressionClassificationMode = 'llm'; // 'llm', 'onnx', 'manual'
  String _expressionDisplayMode = 'sidebar'; // 'sidebar', 'background', 'both'
  bool _expressionRerollSame = false;
  String _expressionFallback = 'neutral'; // 'neutral', 'prime', 'none', 'emoji'
  bool _expressionEmojiBurst = false;
  double _expressionEmojiBurstSize = 28.0; // particle base font size (12–60)

  bool get expressionEnabled => _expressionEnabled;
  String get expressionClassificationMode => _expressionClassificationMode;
  String get expressionDisplayMode => _expressionDisplayMode;
  bool get expressionRerollSame => _expressionRerollSame;
  String get expressionFallback => _expressionFallback;
  bool get expressionEmojiBurst => _expressionEmojiBurst;
  double get expressionEmojiBurstSize => _expressionEmojiBurstSize;

  void load() {
    _expressionEnabled = prefs?.getBool(k('expression_enabled')) ?? false;
    _expressionClassificationMode =
        prefs?.getString(k('expression_classification_mode')) ?? 'llm';
    _expressionDisplayMode =
        prefs?.getString(k('expression_display_mode')) ?? 'sidebar';
    _expressionRerollSame =
        prefs?.getBool(k('expression_reroll_same')) ?? false;
    _expressionFallback =
        prefs?.getString(k('expression_fallback')) ?? 'neutral';
    _expressionEmojiBurst =
        prefs?.getBool(k('expression_emoji_burst')) ?? false;
    _expressionEmojiBurstSize =
        (prefs?.getDouble(k('expression_emoji_burst_size')) ?? 28.0)
            .clamp(12.0, 60.0);
  }

  Future<void> setExpressionEnabled(bool value) async {
    _expressionEnabled = value;
    await prefs?.setBool(k('expression_enabled'), value);
    notify();
  }

  Future<void> setExpressionClassificationMode(String value) async {
    _expressionClassificationMode = value;
    await prefs?.setString(k('expression_classification_mode'), value);
    notify();
  }

  Future<void> setExpressionDisplayMode(String value) async {
    _expressionDisplayMode = value;
    await prefs?.setString(k('expression_display_mode'), value);
    notify();
  }

  Future<void> setExpressionRerollSame(bool value) async {
    _expressionRerollSame = value;
    await prefs?.setBool(k('expression_reroll_same'), value);
    notify();
  }

  Future<void> setExpressionFallback(String value) async {
    _expressionFallback = value;
    await prefs?.setString(k('expression_fallback'), value);
    notify();
  }

  Future<void> setExpressionEmojiBurst(bool value) async {
    _expressionEmojiBurst = value;
    await prefs?.setBool(k('expression_emoji_burst'), value);
    notify();
  }

  Future<void> setExpressionEmojiBurstSize(double value) async {
    _expressionEmojiBurstSize = value.clamp(12.0, 60.0);
    await prefs?.setDouble(
      k('expression_emoji_burst_size'),
      _expressionEmojiBurstSize,
    );
    notify();
  }
}
