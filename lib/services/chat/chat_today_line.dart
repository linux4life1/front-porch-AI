// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Session-scoped today's plan sentence. Lives off ChatService so the god
// file stays under 1,000 lines. In-memory this pass — not on the card.

import 'package:flutter/foundation.dart';

mixin ChatTodayLine on ChangeNotifier {
  String? _todaySentence;
  String? get todaySentence => _todaySentence;

  void setTodaySentence(String? value) {
    final next = value?.trim();
    _todaySentence = (next == null || next.isEmpty) ? null : next;
    notifyListeners();
  }

  /// Null when the planner flag is off. Override to apply the flag.
  String? get todayLine => todaySentence;
}
