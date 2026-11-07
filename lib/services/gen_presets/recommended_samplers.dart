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

import 'package:front_porch_ai/services/gen_presets/catalog_sampler_defaults.dart';
import 'package:front_porch_ai/services/gen_presets/chat_model_id.dart';
import 'package:front_porch_ai/services/gen_presets/gguf_sampling.dart';
import 'package:front_porch_ai/services/gen_presets/sampler_family_table.dart';
import 'package:front_porch_ai/services/gen_presets/sampler_values.dart';

/// Where a model's recommended samplers came from.
enum RecommendedSource {
  /// `general.sampling.*` in the GGUF.
  modelFile,

  /// The provider's model list (`default_parameters`).
  provider,

  /// The built-in [kSamplerFamilies] table.
  family,

  /// Nothing knows this model.
  none,
}

/// A model's recommended samplers and their source. [values] holds only what
/// the source publishes; [resetValue] fills the rest from the app defaults.
@immutable
class RecommendedSamplers {
  const RecommendedSamplers(this.values, this.source, {this.familyLabel});

  static const unknown = RecommendedSamplers(
    SamplerValues(),
    RecommendedSource.none,
  );

  final SamplerValues values;
  final RecommendedSource source;
  final String? familyLabel;

  bool get isEmpty => source == RecommendedSource.none || values.isEmpty;

  /// What a per-value reset goes back to: the model's value, else the app's.
  SamplerValues get resetValues => values.over(SamplerValues.appDefaults);

  /// Shown beside a reset: where the value comes from.
  String get sourceWords => switch (source) {
    RecommendedSource.modelFile => 'recommended by the model file',
    RecommendedSource.provider => 'recommended by the provider',
    RecommendedSource.family =>
      'recommended for ${familyLabel ?? 'this model'}',
    RecommendedSource.none => 'app default',
  };

  /// Wire key for the web relay.
  String get sourceKey => source.name;

  Map<String, Object?> toJson() => {
    'values': values.toJson(),
    'resetValues': resetValues.toJson(),
    'source': sourceKey,
    'sourceWords': sourceWords,
    if (familyLabel != null) 'familyLabel': familyLabel,
  };
}

/// Looks up [model]'s recommended samplers: the model itself first (its GGUF
/// or its provider), then the family table. [readFile] is a test seam.
Future<RecommendedSamplers> recommendedSamplersFor(
  ChatModelId model, {
  Future<SamplerValues> Function(String path) readFile = readGgufSampling,
}) async {
  if (model.isEmpty) return RecommendedSamplers.unknown;
  if (model.localPath != null) {
    final fromFile = await readFile(model.localPath!);
    if (!fromFile.isEmpty) {
      return RecommendedSamplers(fromFile, RecommendedSource.modelFile);
    }
  } else if (model.remoteId != null) {
    final fromHost = CatalogSamplerDefaults.instance.of(model.remoteId!);
    if (!fromHost.isEmpty) {
      return RecommendedSamplers(fromHost, RecommendedSource.provider);
    }
  }
  final family = samplerFamilyFor(model.label);
  if (family != null) {
    return RecommendedSamplers(
      family.values,
      RecommendedSource.family,
      familyLabel: family.label,
    );
  }
  return RecommendedSamplers.unknown;
}
