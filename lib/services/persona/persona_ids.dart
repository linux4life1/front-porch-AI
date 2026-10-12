// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

int _lastPersonaId = 0;

/// A new persona id: a millisecond timestamp, as ids always were, but never
/// one already handed out or stored. Two personas made in the same
/// millisecond (the first-run default and one created right after it, or
/// two from one file) would otherwise share an id and fail the table's
/// unique key. Every new persona id comes from here.
String newPersonaId() {
  final now = DateTime.now().millisecondsSinceEpoch;
  _lastPersonaId = now > _lastPersonaId ? now : _lastPersonaId + 1;
  return '$_lastPersonaId';
}

/// Raises [newPersonaId]'s floor to every numeric id in [ids]: a library's
/// ids can run ahead of this computer's clock (made on another machine, or
/// the clock set back).
void notePersonaIds(Iterable<String> ids) {
  for (final id in ids) {
    final value = int.tryParse(id);
    if (value != null && value > _lastPersonaId) _lastPersonaId = value;
  }
}
