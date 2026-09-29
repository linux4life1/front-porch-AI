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

part of 'image_gen_settings.dart';

String _shiftKey(String workflowId, bool edit) =>
    '${edit ? 'edit' : 'create'}|$workflowId';

Map<String, double> _decodeShifts(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return {
        for (final e in decoded.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
      };
    }
  } on FormatException {
    // A bad value is no override: every graph then posts its own shift.
  }
  return {};
}

/// The sampling shift a Comfy graph posts. A graph posts its own value unless
/// the person moved Shift for that graph, so one graph's slider never changes
/// another's.
extension ImageGenSettingsComfyShift on ImageGenSettings {
  /// The shift the person set for [workflowId], or null when they have not.
  double? comfyShiftFor(String workflowId, {required bool edit}) =>
      _comfyShifts[_shiftKey(workflowId, edit)];

  Future<void> setComfyShift(
    String workflowId,
    double value, {
    required bool edit,
  }) async {
    _comfyShifts[_shiftKey(workflowId, edit)] = value;
    await prefs?.setString(k('comfy_shifts'), jsonEncode(_comfyShifts));
    notify();
  }

  /// Back to the graph's own shift.
  Future<void> clearComfyShift(String workflowId, {required bool edit}) async {
    if (_comfyShifts.remove(_shiftKey(workflowId, edit)) == null) return;
    await prefs?.setString(k('comfy_shifts'), jsonEncode(_comfyShifts));
    notify();
  }
}
