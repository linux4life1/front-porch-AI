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

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/gen_presets/chat_model_id.dart';
import 'package:front_porch_ai/services/gen_presets/recommended_samplers.dart';
import 'package:front_porch_ai/services/gen_presets/sampler_values.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/gen_preset_settings.dart';
import 'package:front_porch_ai/services/storage/settings/generation_settings.dart';

/// What a model switch did to the Generation values, for a toast with Undo.
@immutable
class GenPresetNotice {
  const GenPresetNotice(this.id, this.message);
  final int id;
  final String message;

  Map<String, Object> toJson() => {'id': id, 'message': message};
}

/// Watches which model chat replies come from. When it changes, the model's
/// linked preset loads, or else its recommended values; either way the
/// previous values can be put back with [undo].
///
/// Every switch path (Settings, the chat's Model Settings, a .kcpps that
/// names its model, the web Models page and model chip) ends in the backend
/// settings this reads, so following those settings covers them all.
/// A chat's own Chat Settings values sit on top and are never touched.
class GenPresetFollower {
  GenPresetFollower({
    required this.generation,
    required this.backend,
    required this.presets,
    this.lookup = recommendedSamplersFor,
  });

  final GenerationSettings generation;
  final BackendSettings backend;
  final GenPresetSettings presets;
  final Future<RecommendedSamplers> Function(ChatModelId) lookup;

  ChatModelId _model = ChatModelId.none;
  int _seq = 0;
  int _noticeSeq = 0;
  bool _applying = false;
  SamplerValues? _undoValues;
  String? _undoSlot;

  /// The current chat model's recommended samplers.
  final recommended = ValueNotifier<RecommendedSamplers>(
    RecommendedSamplers.unknown,
  );

  /// The last switch's notice, until it is undone or replaced.
  final notice = ValueNotifier<GenPresetNotice?>(null);

  ChatModelId get model => _model;

  /// Seeds the current model without applying anything: starting the app is
  /// not a switch. Returns once its recommended values are known.
  Future<void> start() async {
    _model = ChatModelId.of(backend);
    await _refreshRecommended(_model, ++_seq);
  }

  /// Call on every settings change; cheap when the model is the same.
  void onSettingsChanged() {
    if (_applying) return;
    final next = ChatModelId.of(backend);
    if (next == _model) return;
    _model = next;
    unawaited(switched(next));
  }

  /// Applies [next]'s preset or recommended values. Public for tests.
  @visibleForTesting
  Future<void> switched(ChatModelId next) async {
    final seq = ++_seq;
    if (next.isEmpty) {
      recommended.value = RecommendedSamplers.unknown;
      return;
    }
    final rec = await _refreshRecommended(next, seq);
    if (rec == null) return; // a newer switch took over
    final before = SamplerValues.capture(generation, backend);
    final beforeSlot = presets.slot;
    final slotValues = beforeSlot == null ? null : presets.presets[beforeSlot];
    final hadEdits = slotValues != null && !slotValues.matchedBy(before);
    final linked = presets.linkedPreset(next.key);
    String message;
    _applying = true;
    try {
      if (linked != null) {
        await presets.presets[linked]!.applyTo(generation, backend);
        await presets.setSlot(linked);
        message = '${next.label} writes with “$linked”.';
      } else if (!rec.isEmpty && !rec.values.matchedBy(before)) {
        await rec.values.applyTo(generation, backend);
        await presets.setSlot(null);
        message = 'Loaded ${next.label}\'s settings, ${rec.sourceWords}.';
      } else {
        return;
      }
    } finally {
      _applying = false;
    }
    if (hadEdits) message += ' Your unsaved changes were set aside.';
    _undoValues = before;
    _undoSlot = beforeSlot;
    notice.value = GenPresetNotice(++_noticeSeq, message);
  }

  /// Puts back the values from before notice [id]'s switch. False when that
  /// notice is no longer the latest.
  Future<bool> undo(int id) async {
    final values = _undoValues;
    if (notice.value?.id != id || values == null) return false;
    _applying = true;
    try {
      await values.applyTo(generation, backend);
      await presets.setSlot(_undoSlot);
    } finally {
      _applying = false;
    }
    _undoValues = null;
    notice.value = null;
    return true;
  }

  /// Looks the current model up again, for a remote model whose provider
  /// list arrived after the switch.
  Future<void> refreshRecommended() async {
    final model = _model;
    RecommendedSamplers rec;
    try {
      rec = await lookup(model);
    } catch (e) {
      debugPrint('[GenPresets] recommended lookup failed: $e');
      return;
    }
    if (model == _model) recommended.value = rec;
  }

  void dismissNotice(int id) {
    if (notice.value?.id == id) notice.value = null;
  }

  Future<RecommendedSamplers?> _refreshRecommended(
    ChatModelId model,
    int seq,
  ) async {
    RecommendedSamplers rec;
    try {
      rec = await lookup(model);
    } catch (e) {
      debugPrint('[GenPresets] recommended lookup failed: $e');
      rec = RecommendedSamplers.unknown;
    }
    if (seq != _seq) return null;
    recommended.value = rec;
    return rec;
  }
}
