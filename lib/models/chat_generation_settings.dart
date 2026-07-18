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
import 'package:front_porch_ai/services/storage_service.dart';

/// Per-session generation parameter overrides.
///
/// Every field is nullable: `null` means "inherit from global defaults"
/// stored in [StorageService].  Only non-null values are serialised to
/// JSON so the DB payload stays minimal.
class ChatGenerationSettings {
  double? temperature;
  double? minP;
  double? topP;
  int? topK;
  double? dryMultiplier;
  double? repeatPenalty;
  int? repeatPenaltyTokens;
  double? xtcThreshold;
  double? xtcProbability;
  bool? dynamicTempEnabled;
  double? dynamicTempRange;
  int? maxLength;
  int? minLength;
  int? contextSize;
  List<String>? stopSequences;
  List<String>? bannedPhrases;
  bool? reasoningEnabled;
  String? reasoningEffort;

  ChatGenerationSettings({
    this.temperature,
    this.minP,
    this.topP,
    this.topK,
    this.dryMultiplier,
    this.repeatPenalty,
    this.repeatPenaltyTokens,
    this.xtcThreshold,
    this.xtcProbability,
    this.dynamicTempEnabled,
    this.dynamicTempRange,
    this.maxLength,
    this.minLength,
    this.contextSize,
    this.stopSequences,
    this.bannedPhrases,
    this.reasoningEnabled,
    this.reasoningEffort,
  });

  /// Whether any field has a non-null override.
  bool get hasOverrides =>
      temperature != null ||
      minP != null ||
      topP != null ||
      topK != null ||
      dryMultiplier != null ||
      repeatPenalty != null ||
      repeatPenaltyTokens != null ||
      xtcThreshold != null ||
      xtcProbability != null ||
      dynamicTempEnabled != null ||
      dynamicTempRange != null ||
      maxLength != null ||
      minLength != null ||
      contextSize != null ||
      stopSequences != null ||
      bannedPhrases != null ||
      reasoningEnabled != null ||
      reasoningEffort != null;

  // ── Resolved getters ────────────────────────────────────────────────────
  // Each returns the per-session override if set, otherwise the global value.

  double resolveTemperature(StorageService s) =>
      temperature ?? s.generationSettings.temperature;
  double resolveMinP(StorageService s) => minP ?? s.generationSettings.minP;
  double resolveTopP(StorageService s) => topP ?? s.generationSettings.topP;
  int resolveTopK(StorageService s) => topK ?? s.generationSettings.topK;
  double resolveDryMultiplier(StorageService s) =>
      dryMultiplier ?? s.generationSettings.dryMultiplier;
  double resolveRepeatPenalty(StorageService s) =>
      repeatPenalty ?? s.generationSettings.repeatPenalty;
  int resolveRepeatPenaltyTokens(StorageService s) =>
      repeatPenaltyTokens ?? s.generationSettings.repeatPenaltyTokens;
  double resolveXtcThreshold(StorageService s) =>
      xtcThreshold ?? s.generationSettings.xtcThreshold;
  double resolveXtcProbability(StorageService s) =>
      xtcProbability ?? s.generationSettings.xtcProbability;
  bool resolveDynamicTempEnabled(StorageService s) =>
      dynamicTempEnabled ?? s.generationSettings.dynamicTempEnabled;
  double resolveDynamicTempRange(StorageService s) =>
      dynamicTempRange ?? s.generationSettings.dynamicTempRange;
  int resolveMaxLength(StorageService s) =>
      maxLength ?? s.generationSettings.maxLength;
  int resolveMinLength(StorageService s) =>
      minLength ?? s.generationSettings.minLength;
  int resolveContextSize(StorageService s) =>
      contextSize ?? s.backendSettings.contextSize;
  List<String> resolveStopSequences(StorageService s) =>
      stopSequences ?? s.generationSettings.stopSequences.toList();
  List<String> resolveBannedPhrases(StorageService s) =>
      bannedPhrases ?? s.realismSettings.bannedPhrases.toList();
  bool resolveReasoningEnabled(StorageService s) =>
      reasoningEnabled ?? s.backendSettings.reasoningEnabled;
  String resolveReasoningEffort(StorageService s) =>
      reasoningEffort ?? s.backendSettings.reasoningEffort;

  // ── JSON serialisation ──────────────────────────────────────────────────

  /// Only writes non-null keys so the stored payload is compact.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (temperature != null) map['temperature'] = temperature;
    if (minP != null) map['min_p'] = minP;
    if (topP != null) map['top_p'] = topP;
    if (topK != null) map['top_k'] = topK;
    if (dryMultiplier != null) map['dry_multiplier'] = dryMultiplier;
    if (repeatPenalty != null) map['repeat_penalty'] = repeatPenalty;
    if (repeatPenaltyTokens != null) {
      map['rep_pen_tokens'] = repeatPenaltyTokens;
    }
    if (xtcThreshold != null) map['xtc_threshold'] = xtcThreshold;
    if (xtcProbability != null) map['xtc_probability'] = xtcProbability;
    if (dynamicTempEnabled != null) {
      map['dynatemp_enabled'] = dynamicTempEnabled;
    }
    if (dynamicTempRange != null) map['dynatemp_range'] = dynamicTempRange;
    if (maxLength != null) map['max_length'] = maxLength;
    if (minLength != null) map['min_length'] = minLength;
    if (contextSize != null) map['context_size'] = contextSize;
    if (stopSequences != null) map['stop_sequences'] = stopSequences;
    if (bannedPhrases != null) map['banned_phrases'] = bannedPhrases;
    if (reasoningEnabled != null) map['reasoning_enabled'] = reasoningEnabled;
    if (reasoningEffort != null) map['reasoning_effort'] = reasoningEffort;
    return map;
  }

  /// Returns the JSON string, or `null` if there are no overrides.
  String? toJsonString() {
    if (!hasOverrides) return null;
    return jsonEncode(toJson());
  }

  /// Parse from a JSON map. Missing keys stay `null` (inherit global).
  factory ChatGenerationSettings.fromJson(Map<String, dynamic> json) {
    return ChatGenerationSettings(
      temperature: (json['temperature'] as num?)?.toDouble(),
      minP: (json['min_p'] as num?)?.toDouble(),
      topP: (json['top_p'] as num?)?.toDouble(),
      topK: (json['top_k'] as num?)?.toInt(),
      dryMultiplier: (json['dry_multiplier'] as num?)?.toDouble(),
      repeatPenalty: (json['repeat_penalty'] as num?)?.toDouble(),
      repeatPenaltyTokens: (json['rep_pen_tokens'] as num?)?.toInt(),
      xtcThreshold: (json['xtc_threshold'] as num?)?.toDouble(),
      xtcProbability: (json['xtc_probability'] as num?)?.toDouble(),
      dynamicTempEnabled: json['dynatemp_enabled'] as bool?,
      dynamicTempRange: (json['dynatemp_range'] as num?)?.toDouble(),
      maxLength: (json['max_length'] as num?)?.toInt(),
      minLength: (json['min_length'] as num?)?.toInt(),
      contextSize: (json['context_size'] as num?)?.toInt(),
      stopSequences: (json['stop_sequences'] as List?)?.cast<String>(),
      bannedPhrases: (json['banned_phrases'] as List?)?.cast<String>(),
      reasoningEnabled: json['reasoning_enabled'] as bool?,
      reasoningEffort: json['reasoning_effort'] as String?,
    );
  }

  /// Parse from a nullable JSON string (the raw DB column value).
  /// Returns an empty (all-null) instance if the string is null or empty.
  factory ChatGenerationSettings.fromJsonString(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) {
      return ChatGenerationSettings();
    }
    try {
      return ChatGenerationSettings.fromJson(
        jsonDecode(jsonString) as Map<String, dynamic>,
      );
    } catch (_) {
      return ChatGenerationSettings();
    }
  }

  /// Create a deep copy.
  ChatGenerationSettings copy() => ChatGenerationSettings.fromJson(toJson());
}
