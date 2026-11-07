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

import 'package:front_porch_ai/services/gen_presets/sampler_values.dart';

/// Per-model `default_parameters` a provider's model list publishes
/// (OpenRouter does). Filled as the list is fetched, read when a model is
/// picked from it.
class CatalogSamplerDefaults {
  CatalogSamplerDefaults._();
  static final instance = CatalogSamplerDefaults._();

  final Map<String, SamplerValues> _byModel = {};

  SamplerValues of(String modelId) =>
      _byModel[modelId] ?? const SamplerValues();

  /// Records [raw] (a model entry's `default_parameters`) for [modelId].
  /// Anything unreadable is ignored.
  void remember(String modelId, Object? raw) {
    final values = fromDefaultParameters(raw);
    if (values.isEmpty) {
      _byModel.remove(modelId);
    } else {
      _byModel[modelId] = values;
    }
  }

  static SamplerValues fromDefaultParameters(Object? raw) {
    if (raw is! Map) return const SamplerValues();
    double? d(String k) {
      final v = raw[k];
      return v is num && v.isFinite ? v.toDouble() : null;
    }

    final topK = raw['top_k'];
    return SamplerValues(
      temperature: d('temperature'),
      topP: d('top_p'),
      topK: topK is num && topK.isFinite ? topK.round() : null,
      minP: d('min_p'),
      repeatPenalty: d('repetition_penalty'),
    );
  }

  void clearForTest() => _byModel.clear();
}
