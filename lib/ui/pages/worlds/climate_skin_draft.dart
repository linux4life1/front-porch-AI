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

import 'package:flutter/widgets.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show WeatherStance;

/// One weather condition's rename while the climate editor is open.
class SkinDraft {
  String label = '';
  String emoji = '';
  WeatherStance? stance;
  String flavour = '';

  bool get active => label.trim().isNotEmpty;
}

/// What the climate editor holds: Save's output plus the typed input Save
/// drops while it is unfinished (a weather renamed before its danger level is
/// picked), so closing over either asks first.
String climateEditState(
  String draftJson,
  Map<String, SkinDraft> skins,
  List<Map<String, TextEditingController>> fields,
  Map<String, List<TextEditingController>> fieldLists,
) => jsonEncode([
  draftJson,
  for (final s in skins.values) [s.label, s.emoji, s.stance?.name, s.flavour],
  for (final m in fields) [for (final f in m.values) f.text],
  for (final l in fieldLists.values) [for (final f in l) f.text],
]);
