// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// sessions.needs_vector used to be a flat hunger→int map. Wrapping it lets
// the hygiene-catastrophe ack survive reload without a schema bump. Legacy
// blobs still decode.

import 'package:front_porch_ai/services/chat/needs_simulation.dart';

Map<String, dynamic> encodeNeedsPersist(NeedsSimulation sim) {
  return {
    'vector': Map<String, int>.from(sim.vector),
    'hygiene_crisis_acked': sim.hygieneCrisisAcked.toList(),
  };
}

void applyNeedsPersist(NeedsSimulation sim, Object? raw) {
  if (raw is! Map) return;
  if (raw['vector'] is Map) {
    sim.restoreFromSnapshot(raw);
    return;
  }
  sim.restoreFromSnapshot({'vector': raw});
}
