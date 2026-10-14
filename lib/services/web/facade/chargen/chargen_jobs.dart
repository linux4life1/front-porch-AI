// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';

/// A relay refusal: the route answers [status] with [error].
Map<String, dynamic> chargenRefuse(int status, String error) => {
  'ok': false,
  'status': status,
  'error': error,
};

/// Lets a progress event through at most every 120 ms. The hub paints
/// every ~33 ms anyway; a phone needs far fewer frames.
class ProgressThrottle {
  var _sentAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get ready {
    final now = DateTime.now();
    if (now.difference(_sentAt).inMilliseconds < 120) return false;
    _sentAt = now;
    return true;
  }
}

/// The facts [card] carries now, in the relay's facts shape. Warmth is not
/// stored on a card; it is read back from the opening bond.
IdentityFacts identityFactsOfCard(CharacterCard card) {
  final e = card.frontPorchExtensions;
  if (e == null) return IdentityFacts(creatorNotes: card.creatorNotes);
  return IdentityFacts(
    birthday: e.birthday,
    occupation: e.occupation,
    occupationBrief: e.occupationBrief,
    hours: e.hours,
    workDays: e.workDays,
    currentTask: e.currentTask,
    warmth: e.shortTermBond > 0
        ? 'warm'
        : e.shortTermBond < 0
        ? 'cold'
        : 'strangers',
    shortTermBond: e.shortTermBond,
    trustLevel: e.trustLevel,
    ambitions: e.ambitions,
    planLines: e.planLines,
    likes: e.likes,
    dislikes: e.dislikes,
    intimateInto: e.intimateInto,
    intimateNotInto: e.intimateNotInto,
    creatorNotes: card.creatorNotes,
  );
}

/// Write [f] onto [card] exactly as the author left it: unlike
/// [applyIdentityFacts], an emptied list or field stays empty, because on
/// the Profile step an empty value is the author's choice.
void writeEditedFacts(CharacterCard card, IdentityFacts f) {
  applyIdentityFacts(card, f);
  final e = card.frontPorchExtensions!;
  e
    ..birthday = f.birthday
    ..occupation = f.occupation
    ..occupationBrief = f.occupationBrief
    ..hours = f.hours
    ..currentTask = f.currentTask
    ..ambitions = List.unmodifiable(f.ambitions)
    ..planLines = List.unmodifiable(f.planLines)
    ..likes = List.unmodifiable(f.likes)
    ..dislikes = List.unmodifiable(f.dislikes)
    ..intimateInto = List.unmodifiable(f.intimateInto)
    ..intimateNotInto = List.unmodifiable(f.intimateNotInto);
  card.creatorNotes = f.creatorNotes;
}

/// The three profile texts in a request body, or null when one is missing.
({String description, String personality, String scenario})? profileTextsOf(
  Map<String, dynamic> body,
) {
  final d = body['description'];
  final p = body['personality'];
  final s = body['scenario'];
  if (d is! String || p is! String || s is! String) return null;
  return (description: d, personality: p, scenario: s);
}
