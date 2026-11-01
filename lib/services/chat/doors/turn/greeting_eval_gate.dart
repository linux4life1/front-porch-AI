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

/// Bumped by the cast door's greeting invalidation (selectGreeting,
/// startNewChat, setActiveCharacter, setActiveGroup, loadSession, the last
/// session's load, importChatPackage, forkFromMessage) so a late unawaited
/// post-greeting eval cannot stomp a later opening. File scope, as it always
/// was: one generation for the process.
int _greetingEvalGen = 0;

const Object _kGreetingEvalToken = #_greetingEvalToken;
const Object _kGreetingEvalIndex = #_greetingEvalIndex;

/// Set when the post-greeting eval passes its guards (not skipped solely
/// because the active character is null). Tests prove group unauthored alts
/// reach the eval path.
@visibleForTesting
bool testPostGreetingEvalEntered = false;

/// The greeting eval's stale-apply guard: the generation an opening's eval
/// is checked against, and the zone values it runs under.
class GreetingEvalGate {
  const GreetingEvalGate();

  /// The live greeting-eval generation.
  int get gen => _greetingEvalGen;

  /// A new opening: every earlier greeting eval is stale from here on.
  void bump() => _greetingEvalGen++;

  /// The zone values a greeting eval with [token] and [index] runs under.
  Map<Object?, Object?> zone(int token, int index) => {
    _kGreetingEvalToken: token,
    _kGreetingEvalIndex: index,
  };

  /// Stale when THIS eval's captured token is no longer the live gen.
  /// [bump] always moves the gen, so a later opening stale-gates the
  /// earlier apply without a shared nullable slot. A missing zone token is
  /// not a greeting apply (normal turn evals).
  bool isStale() {
    final token = Zone.current[_kGreetingEvalToken] as int?;
    if (token == null) return false;
    return token != _greetingEvalGen;
  }

  /// The eval passed its guards ([testPostGreetingEvalEntered]).
  void markEntered() => testPostGreetingEvalEntered = true;

  /// A swipe re-seeds the opening: the next eval must pass the guards again.
  void clearEntered() => testPostGreetingEvalEntered = false;
}
