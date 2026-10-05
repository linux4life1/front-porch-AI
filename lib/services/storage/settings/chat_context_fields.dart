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

// Leaves, not kobold.dart: the barrel loops back through storage_service.dart.
import 'package:front_porch_ai/services/kobold/kobold_context_owner.dart';
import 'package:front_porch_ai/services/kobold/kobold_context_verdict.dart'
    show kKoboldContextFloor;

import 'settings_base.dart';

/// The user's own context, kept while a preset is chosen.
const String _kContextBeforePreset = 'context_size_before_preset';

/// Chat's context, and the user's own while a preset is chosen. A mixin
/// beside [BackendSettings] because that file is at the size limit.
///
/// Choosing a preset copies its context in, as the context in use (the
/// prompt budget, the cards and the phone read this one number). The user's
/// own is kept when a preset is first chosen and comes back when the preset
/// is cleared, or a model without one is picked; going from one preset to
/// another keeps it. With none kept (a preset chosen before the app kept
/// it), clearing keeps the number in use, but never under 16,384. Every way
/// a preset is chosen or cleared comes through [followPresetContext], on
/// the desktop and on the phone, and so does a launch dropping one.
mixin ChatContextFields on SettingsBase {
  // 16384 (was 8192): modern models all serve 16k+, and the 2048-token
  // generation reserve (generation_settings.dart) plus lorebooks/journal
  // left an 8k window tight on chat history. Users with a saved value
  // keep theirs; this only seeds fresh installs.
  int _contextSize = 16384;
  int? _contextBeforePreset;

  String get backendType;
  String? get activeKcppsPath;

  /// The chosen preset sets chat's context ([koboldPresetOwnsContext]).
  bool get presetOwnsContext =>
      koboldPresetOwnsContext(backend: backendType, kcppsPath: activeKcppsPath);

  int get contextSize => _contextSize;

  /// The user's own context, kept while a preset is chosen; null otherwise.
  int? get contextBeforePreset => _contextBeforePreset;

  /// [presetContext]: what the preset chosen at start sets, if anything. A
  /// context saved since wins, as it always has.
  void loadChatContext(int? presetContext) {
    _contextSize =
        prefs?.getInt(k('context_size')) ?? presetContext ?? _contextSize;
    _contextBeforePreset = prefs?.getInt(k(_kContextBeforePreset));
  }

  Future<void> setContextSize(int value) async {
    // A different number the user sets while a preset is chosen (one left
    // on another backend, where it does not set the context) is their own
    // from then on: it is what comes back. The phone sends the context it
    // read with every save, which is not a choice.
    if (_contextBeforePreset != null && value != _contextSize) {
      await _keepOwnContext(value);
    }
    await _storeContext(value);
    notify();
  }

  /// The chosen preset went from one ([hadPreset]) to another, to one, or to
  /// none ([hasPreset]). [presetContext] is what the new one sets.
  Future<void> followPresetContext({
    required bool hadPreset,
    required bool hasPreset,
    int? presetContext,
  }) async {
    if (hasPreset) {
      if (!hadPreset) await _keepOwnContext(_contextSize);
      if (presetContext != null) await _storeContext(presetContext);
      return;
    }
    if (!hadPreset) return;
    final own = _contextBeforePreset;
    if (own != null) {
      // Exactly as the user had it, under 16,384 too: it is theirs.
      await _keepOwnContext(null);
      await _storeContext(own);
    } else if (_contextSize < kKoboldContextFloor) {
      // Chosen before the app kept the user's own (an upgrade): the number in
      // use stays, but a small preset's is not left behind.
      await _storeContext(kKoboldContextFloor);
    }
  }

  Future<void> _storeContext(int value) async {
    _contextSize = value;
    await prefs?.setInt(k('context_size'), value);
  }

  Future<void> _keepOwnContext(int? value) async {
    _contextBeforePreset = value;
    if (value == null) {
      await prefs?.remove(k(_kContextBeforePreset));
    } else {
      await prefs?.setInt(k(_kContextBeforePreset), value);
    }
  }
}
