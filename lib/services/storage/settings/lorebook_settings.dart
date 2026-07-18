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

import 'dart:convert';

import 'settings_base.dart';

/// Global lorebook engine settings (SillyTavern "World Info" globals).
/// Book-level and per-entry values override these where present
/// (entry.scanDepth ?? book.scanDepth ?? global, etc.).
///
/// No settings UI yet — the engine consumes the defaults below; Phase 4 of
/// docs/design/lorebook-parity.md exposes them.
class LorebookSettings with SettingsBase {
  /// How many recent messages the keyword scan sees. 1 = the just-arrived
  /// message only, which preserves the long-standing FPAI cadence (sticky
  /// turns already provide multi-turn persistence). ST's default is 2 —
  /// users wanting exact ST cadence can raise this.
  int _scanDepth = 1;

  /// Prefix scanned messages with "Name: " (ST default). Keys that equal a
  /// character/persona name then match on every one of their messages.
  bool _includeNames = true;

  /// Whether activated entries' content is re-scanned so lore can trigger
  /// other lore (ST default on).
  bool _recursiveScan = true;

  /// Hard stop for recursion sweeps. 0 = unlimited (an internal safety cap
  /// still applies).
  int _maxRecursionSteps = 0;

  /// Lore token budget as a percentage of the context size (ST default 25).
  int _budgetPercent = 25;

  /// Absolute token cap applied after the percentage. 0 = off.
  int _budgetCap = 0;

  /// App-wide {{setglobalvar}}/{{getglobalvar}} macro variables (ST keeps
  /// these in settings too). Persisted as one JSON map.
  final Map<String, String> _globalMacroVars = {};

  int get scanDepth => _scanDepth;
  bool get includeNames => _includeNames;
  bool get recursiveScan => _recursiveScan;
  int get maxRecursionSteps => _maxRecursionSteps;
  int get budgetPercent => _budgetPercent;
  int get budgetCap => _budgetCap;

  String? getGlobalMacroVar(String name) => _globalMacroVars[name];

  void setGlobalMacroVar(String name, String value) {
    _globalMacroVars[name] = value;
    // Fire-and-forget persist; no notify (prompt-build internals, not UI).
    prefs?.setString(k('macro_global_vars'), jsonEncode(_globalMacroVars));
  }

  void load() {
    _scanDepth = prefs?.getInt(k('lorebook_scan_depth')) ?? 1;
    _includeNames = prefs?.getBool(k('lorebook_include_names')) ?? true;
    _recursiveScan = prefs?.getBool(k('lorebook_recursive_scan')) ?? true;
    _maxRecursionSteps = prefs?.getInt(k('lorebook_max_recursion_steps')) ?? 0;
    _budgetPercent = prefs?.getInt(k('lorebook_budget_percent')) ?? 25;
    _budgetCap = prefs?.getInt(k('lorebook_budget_cap')) ?? 0;
    _globalMacroVars.clear();
    final rawVars = prefs?.getString(k('macro_global_vars'));
    if (rawVars != null && rawVars.isNotEmpty) {
      try {
        (jsonDecode(rawVars) as Map).forEach((key, v) {
          _globalMacroVars[key.toString()] = v.toString();
        });
      } catch (_) {}
    }
  }

  Future<void> setScanDepth(int v) async {
    _scanDepth = v.clamp(1, 100);
    await prefs?.setInt(k('lorebook_scan_depth'), _scanDepth);
    notify();
  }

  Future<void> setIncludeNames(bool v) async {
    _includeNames = v;
    await prefs?.setBool(k('lorebook_include_names'), v);
    notify();
  }

  Future<void> setRecursiveScan(bool v) async {
    _recursiveScan = v;
    await prefs?.setBool(k('lorebook_recursive_scan'), v);
    notify();
  }

  Future<void> setMaxRecursionSteps(int v) async {
    _maxRecursionSteps = v.clamp(0, 10);
    await prefs?.setInt(k('lorebook_max_recursion_steps'), _maxRecursionSteps);
    notify();
  }

  Future<void> setBudgetPercent(int v) async {
    _budgetPercent = v.clamp(1, 100);
    await prefs?.setInt(k('lorebook_budget_percent'), _budgetPercent);
    notify();
  }

  Future<void> setBudgetCap(int v) async {
    _budgetCap = v < 0 ? 0 : v;
    await prefs?.setInt(k('lorebook_budget_cap'), _budgetCap);
    notify();
  }
}
