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

/// Extract the option list for one node input from a GET /object_info
/// payload, e.g. node 'CheckpointLoaderSimple' input 'ckpt_name'. ComfyUI
/// encodes enum inputs as `[ [options...], {meta} ]`. Pure — unit-tested.
List<String> comfyOptionsFromObjectInfo(
  Map<String, dynamic> objectInfo,
  String nodeType,
  String inputName,
) {
  final node = objectInfo[nodeType];
  if (node is! Map) return const [];
  final input = node['input'];
  if (input is! Map) return const [];
  for (final section in ['required', 'optional']) {
    final sec = input[section];
    if (sec is! Map) continue;
    final spec = sec[inputName];
    if (spec is List && spec.isNotEmpty && spec.first is List) {
      return (spec.first as List).map((e) => e.toString()).toList();
    }
  }
  return const [];
}
