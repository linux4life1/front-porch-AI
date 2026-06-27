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

/// Generation / sampling settings (system prompt, temperature, penalties,
/// stop sequences, context/max length, etc.).
///
/// Lifted mechanically from StorageService (Stage 7). Direct use via
/// StorageService.generationSettings after final shim migration cleanup.
/// All sets persist with beta_ prefix and call notify() on owner.
class GenerationSettings with SettingsBase {
  static const String defaultSystemPrompt =
      "You are an immersive roleplay partner. Embody {{char}} completely — personality, appearance, thought processes, emotions, behaviors, and speech patterns. You may also roleplay as any side characters introduced.\n\nEngage with {{user}} by depicting {{char}}'s actions, emotions, and dialogue. Develop the plot slowly and organically while driving the scenario forward. Never write {{user}}'s speech, actions, or decisions — allow them full control of their character.\n\nWrite in a vivid, creative, varied, and descriptive style. Use rich sensory detail for the environment, people, and events. Make each reply unique and end with an action or dialogue to keep momentum.\n\nMaintain consistency with established details — clothing, time of day, location, and prior events. Stay in character at all times.";

  String _systemPrompt = defaultSystemPrompt;
  double _minP = 0.1;
  double _temperature = 0.7;
  double _repeatPenalty = 1.1;
  int _repeatPenaltyTokens = 64;
  bool _dynamicTempEnabled = false;
  double _dynamicTempRange = 0.7;
  bool _dynamicResponses = false;
  int _dynamicResponseInterval = 60;
  double _xtcThreshold = 0.1;
  double _xtcProbability = 0.5;
  int _maxLength = 1024;
  int _minLength = 0;
  List<String> _stopSequences = [
    "\nUser:",
    "\n###",
    "\nScenario:",
    "<END>",
    "</END>",
    "[END]",
    "<|end|>",
    "<START>",
    "\nSystem:",
    "\n(Note:",
    "\n[Note:",
    "\n{Note:",
  ];

  String get systemPrompt => _systemPrompt;
  double get minP => _minP;
  double get temperature => _temperature;
  double get repeatPenalty => _repeatPenalty;
  int get repeatPenaltyTokens => _repeatPenaltyTokens;
  bool get dynamicTempEnabled => _dynamicTempEnabled;
  double get dynamicTempRange => _dynamicTempRange;
  bool get dynamicResponses => _dynamicResponses;
  int get dynamicResponseInterval => _dynamicResponseInterval;
  double get xtcThreshold => _xtcThreshold;
  double get xtcProbability => _xtcProbability;
  int get maxLength => _maxLength;
  int get minLength => _minLength;
  List<String> get stopSequences => List.unmodifiable(_stopSequences);

  void load() {
    _systemPrompt = prefs?.getString(k('system_prompt')) ?? _systemPrompt;
    _minP = prefs?.getDouble(k('min_p')) ?? _minP;
    _temperature = prefs?.getDouble(k('temperature')) ?? _temperature;
    _repeatPenalty = prefs?.getDouble(k('repeat_penalty')) ?? _repeatPenalty;
    _repeatPenaltyTokens =
        prefs?.getInt(k('repeat_penalty_tokens')) ?? _repeatPenaltyTokens;
    _dynamicTempEnabled =
        prefs?.getBool(k('dynamic_temp_enabled')) ?? _dynamicTempEnabled;
    _dynamicTempRange =
        prefs?.getDouble(k('dynamic_temp_range')) ?? _dynamicTempRange;
    _dynamicResponses =
        prefs?.getBool(k('dynamic_responses')) ?? _dynamicResponses;
    _dynamicResponseInterval =
        prefs?.getInt(k('dynamic_response_interval')) ?? _dynamicResponseInterval;
    _xtcThreshold = prefs?.getDouble(k('xtc_threshold')) ?? _xtcThreshold;
    _xtcProbability = prefs?.getDouble(k('xtc_probability')) ?? _xtcProbability;
    _maxLength = prefs?.getInt(k('max_length')) ?? _maxLength;
    _minLength = prefs?.getInt(k('min_length')) ?? _minLength;
    _stopSequences =
        prefs?.getStringList(k('stop_sequences')) ?? _stopSequences;
    // Ensure essential stop sequences are always present (migration for existing users)
    const essentialStops = ['</END>', '[END]', '<|end|>', '<START>'];
    bool added = false;
    for (final s in essentialStops) {
      if (!_stopSequences.contains(s)) {
        _stopSequences.add(s);
        added = true;
      }
    }
    if (added) {
      prefs?.setStringList(k('stop_sequences'), _stopSequences);
    }
  }

  Future<void> setSystemPrompt(String value) async {
    _systemPrompt = value;
    await prefs?.setString(k('system_prompt'), value);
    notify();
  }

  Future<void> setMinP(double value) async {
    _minP = value;
    await prefs?.setDouble(k('min_p'), value);
    notify();
  }

  Future<void> setTemperature(double value) async {
    _temperature = value;
    await prefs?.setDouble(k('temperature'), value);
    notify();
  }

  Future<void> setRepeatPenalty(double value) async {
    _repeatPenalty = value;
    await prefs?.setDouble(k('repeat_penalty'), value);
    notify();
  }

  Future<void> setRepeatPenaltyTokens(int value) async {
    _repeatPenaltyTokens = value;
    await prefs?.setInt(k('repeat_penalty_tokens'), value);
    notify();
  }

  Future<void> setDynamicTempEnabled(bool value) async {
    _dynamicTempEnabled = value;
    await prefs?.setBool(k('dynamic_temp_enabled'), value);
    notify();
  }

  Future<void> setDynamicTempRange(double value) async {
    _dynamicTempRange = value;
    await prefs?.setDouble(k('dynamic_temp_range'), value);
    notify();
  }

  Future<void> setDynamicResponses(bool value) async {
    _dynamicResponses = value;
    await prefs?.setBool(k('dynamic_responses'), value);
    notify();
  }

  Future<void> setDynamicResponseInterval(int value) async {
    _dynamicResponseInterval = value;
    await prefs?.setInt(k('dynamic_response_interval'), value);
    notify();
  }

  Future<void> setXtcThreshold(double value) async {
    _xtcThreshold = value;
    await prefs?.setDouble(k('xtc_threshold'), value);
    notify();
  }

  Future<void> setXtcProbability(double value) async {
    _xtcProbability = value;
    await prefs?.setDouble(k('xtc_probability'), value);
    notify();
  }

  Future<void> setMaxLength(int value) async {
    _maxLength = value;
    await prefs?.setInt(k('max_length'), value);
    notify();
  }

  Future<void> setMinLength(int value) async {
    _minLength = value;
    await prefs?.setInt(k('min_length'), value);
    notify();
  }

  Future<void> setStopSequences(List<String> value) async {
    _stopSequences = value;
    await prefs?.setStringList(k('stop_sequences'), value);
    notify();
  }

  Future<void> addStopSequence(String value) async {
    if (!_stopSequences.contains(value)) {
      _stopSequences.add(value);
      await prefs?.setStringList(k('stop_sequences'), _stopSequences);
      notify();
    }
  }

  Future<void> removeStopSequence(String value) async {
    if (_stopSequences.remove(value)) {
      await prefs?.setStringList(k('stop_sequences'), _stopSequences);
      notify();
    }
  }
}
