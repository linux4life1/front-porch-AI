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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/generation_settings.dart';

/// The values a generation preset holds: how a model writes, not what the
/// user or the machine wants. Context size, banned phrases, the sanitizer and
/// the display buffer stay out on purpose.
///
/// Every field is nullable. A saved preset fills all of them; a model's
/// recommended values fill only what its source publishes, and applying them
/// leaves the rest alone.
@immutable
class SamplerValues {
  const SamplerValues({
    this.temperature,
    this.minP,
    this.topP,
    this.topK,
    this.repeatPenalty,
    this.repeatPenaltyTokens,
    this.xtcThreshold,
    this.xtcProbability,
    this.dryMultiplier,
    this.dynamicTempEnabled,
    this.dynamicTempRange,
    this.maxLength,
    this.reasoningEnabled,
    this.reasoningEffort,
    this.stopSequences,
  });

  final double? temperature;
  final double? minP;
  final double? topP;
  final int? topK;
  final double? repeatPenalty;
  final int? repeatPenaltyTokens;
  final double? xtcThreshold;
  final double? xtcProbability;
  final double? dryMultiplier;
  final bool? dynamicTempEnabled;
  final double? dynamicTempRange;
  final int? maxLength;
  final bool? reasoningEnabled;
  final String? reasoningEffort;
  final List<String>? stopSequences;

  /// The app's own defaults for the sampler knobs, the last fallback for a
  /// per-value reset. Kept equal to [GenerationSettings]' field defaults
  /// (pinned by a test).
  static const SamplerValues appDefaults = SamplerValues(
    temperature: 0.7,
    minP: 0.1,
    topP: 0.9,
    topK: 0,
    repeatPenalty: 1.1,
    repeatPenaltyTokens: 1024,
    xtcThreshold: 0.1,
    xtcProbability: 0.0,
    dryMultiplier: 0.0,
    dynamicTempEnabled: false,
    dynamicTempRange: 0.7,
    maxLength: 2048,
  );

  bool get isEmpty => toJson().isEmpty;

  /// The live global values, every field filled.
  factory SamplerValues.capture(GenerationSettings g, BackendSettings b) =>
      SamplerValues(
        temperature: g.temperature,
        minP: g.minP,
        topP: g.topP,
        topK: g.topK,
        repeatPenalty: g.repeatPenalty,
        repeatPenaltyTokens: g.repeatPenaltyTokens,
        xtcThreshold: g.xtcThreshold,
        xtcProbability: g.xtcProbability,
        dryMultiplier: g.dryMultiplier,
        dynamicTempEnabled: g.dynamicTempEnabled,
        dynamicTempRange: g.dynamicTempRange,
        maxLength: g.maxLength,
        reasoningEnabled: b.reasoningEnabled,
        reasoningEffort: b.reasoningEffort,
        stopSequences: g.stopSequences,
      );

  /// Writes every non-null field to the global settings. Fields left null
  /// keep their live value.
  Future<void> applyTo(GenerationSettings g, BackendSettings b) async {
    if (temperature != null) await g.setTemperature(temperature!);
    if (minP != null) await g.setMinP(minP!);
    if (topP != null) await g.setTopP(topP!);
    if (topK != null) await g.setTopK(topK!);
    if (repeatPenalty != null) await g.setRepeatPenalty(repeatPenalty!);
    if (repeatPenaltyTokens != null) {
      await g.setRepeatPenaltyTokens(repeatPenaltyTokens!);
    }
    if (xtcThreshold != null) await g.setXtcThreshold(xtcThreshold!);
    if (xtcProbability != null) await g.setXtcProbability(xtcProbability!);
    if (dryMultiplier != null) await g.setDryMultiplier(dryMultiplier!);
    if (dynamicTempEnabled != null) {
      await g.setDynamicTempEnabled(dynamicTempEnabled!);
    }
    if (dynamicTempRange != null) {
      await g.setDynamicTempRange(dynamicTempRange!);
    }
    if (maxLength != null) await g.setMaxLength(maxLength!);
    if (reasoningEnabled != null) {
      await b.setReasoningEnabled(reasoningEnabled!);
    }
    if (reasoningEffort != null) await b.setReasoningEffort(reasoningEffort!);
    if (stopSequences != null) {
      await g.setStopSequences(List.of(stopSequences!));
    }
  }

  /// [this] with [base] filling every field this leaves null.
  SamplerValues over(SamplerValues base) => SamplerValues(
    temperature: temperature ?? base.temperature,
    minP: minP ?? base.minP,
    topP: topP ?? base.topP,
    topK: topK ?? base.topK,
    repeatPenalty: repeatPenalty ?? base.repeatPenalty,
    repeatPenaltyTokens: repeatPenaltyTokens ?? base.repeatPenaltyTokens,
    xtcThreshold: xtcThreshold ?? base.xtcThreshold,
    xtcProbability: xtcProbability ?? base.xtcProbability,
    dryMultiplier: dryMultiplier ?? base.dryMultiplier,
    dynamicTempEnabled: dynamicTempEnabled ?? base.dynamicTempEnabled,
    dynamicTempRange: dynamicTempRange ?? base.dynamicTempRange,
    maxLength: maxLength ?? base.maxLength,
    reasoningEnabled: reasoningEnabled ?? base.reasoningEnabled,
    reasoningEffort: reasoningEffort ?? base.reasoningEffort,
    stopSequences: stopSequences ?? base.stopSequences,
  );

  /// Whether every field this sets matches [other]. Fields this leaves null
  /// are not compared, so recommended values match a fuller live set.
  bool matchedBy(SamplerValues other) {
    final mine = toJson();
    final theirs = other.toJson();
    for (final e in mine.entries) {
      final t = theirs[e.key];
      if (e.value is List) {
        if (t is! List || !listEquals(e.value as List, t)) return false;
      } else if (e.value is double && t is num) {
        if (((e.value as double) - t.toDouble()).abs() > 1e-6) return false;
      } else if (e.value != t) {
        return false;
      }
    }
    return true;
  }

  /// Wire keys are shared by the prefs store and the web relay.
  Map<String, Object> toJson() => {
    'temperature': ?temperature,
    'minP': ?minP,
    'topP': ?topP,
    'topK': ?topK,
    'repeatPenalty': ?repeatPenalty,
    'repeatPenaltyTokens': ?repeatPenaltyTokens,
    'xtcThreshold': ?xtcThreshold,
    'xtcProbability': ?xtcProbability,
    'dryMultiplier': ?dryMultiplier,
    'dynamicTempEnabled': ?dynamicTempEnabled,
    'dynamicTempRange': ?dynamicTempRange,
    'maxLength': ?maxLength,
    'reasoningEnabled': ?reasoningEnabled,
    'reasoningEffort': ?reasoningEffort,
    'stopSequences': ?stopSequences,
  };

  /// Reads whatever is readable; a mistyped field is dropped, never thrown.
  factory SamplerValues.fromJson(Object? raw) {
    if (raw is! Map) return const SamplerValues();
    double? d(String k) {
      final v = raw[k];
      return v is num && v.isFinite ? v.toDouble() : null;
    }

    int? i(String k) {
      final v = raw[k];
      return v is num && v.isFinite ? v.round() : null;
    }

    bool? b(String k) => raw[k] is bool ? raw[k] as bool : null;
    final stops = raw['stopSequences'];
    final effort = raw['reasoningEffort'];
    return SamplerValues(
      temperature: d('temperature'),
      minP: d('minP'),
      topP: d('topP'),
      topK: i('topK'),
      repeatPenalty: d('repeatPenalty'),
      repeatPenaltyTokens: i('repeatPenaltyTokens'),
      xtcThreshold: d('xtcThreshold'),
      xtcProbability: d('xtcProbability'),
      dryMultiplier: d('dryMultiplier'),
      dynamicTempEnabled: b('dynamicTempEnabled'),
      dynamicTempRange: d('dynamicTempRange'),
      maxLength: i('maxLength'),
      reasoningEnabled: b('reasoningEnabled'),
      reasoningEffort: effort is String && effort.isNotEmpty ? effort : null,
      stopSequences: stops is List
          ? [
              for (final s in stops)
                if (s is String) s,
            ]
          : null,
    );
  }
}
