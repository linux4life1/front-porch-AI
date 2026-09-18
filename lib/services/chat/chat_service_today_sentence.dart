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

part of '../chat_service.dart';

/// Session-scoped today sentence. Day-clear is on the clock advance.
mixin ChatServiceTodaySentence on ChangeNotifier {
  String? _todaySentence;
  String? _todayObjectiveId;
  String? _todayObjectiveText;
  void Function(String? held)? _onTodayAbandoned;

  String? get todaySentence => _todaySentence;
  String? get todayObjectiveId => _todayObjectiveId;

  void setTodaySentence(String? value) {
    final next = value?.trim();
    _todaySentence = (next == null || next.isEmpty) ? null : next;
    notifyListeners();
  }

  /// User X or empty [today:] tag. Setter stays a plain clear.
  void abandonToday() {
    final held = todaySentence;
    setTodaySentence(null);
    _onTodayAbandoned?.call(held);
  }

  String? get todayLine => todaySentence;

  /// Drop the RAM hold. Does not touch the DB row.
  void _clearTodayPointer() {
    _todaySentence = null;
    _todayObjectiveId = null;
    _todayObjectiveText = null;
    notifyListeners();
  }
}
