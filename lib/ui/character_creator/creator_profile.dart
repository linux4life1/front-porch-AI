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

import 'package:flutter/widgets.dart';

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';

/// The Profile step's own state (#530): the paused run Phase A handed back,
/// the profile rewrite streaming in, the facts re-read, and Phase B while it
/// runs. Held by `CreatorState`, which notifies; the work itself is
/// `CreatorProfileWriter` and `CreatorGenerationCore.continueGeneration`.
/// The twin of `CreatorGreetings`.
class CreatorProfile {
  /// What Phase A wrote, kept as plain data so Next (Phase B) and every
  /// rewrite run from it. Null before a profile exists.
  GenPausedRun? paused;

  /// Phase B has written the rest; Next on the Profile step just moves on.
  bool completed = false;

  /// The identity facts as last read (the facts card's opening stance).
  IdentityFacts? facts;

  /// The profile rewrite is running, what it has streamed so far, and the
  /// run Stop cancels.
  bool rewriting = false;
  ProfileStreamView stream = const ProfileStreamView();
  CharacterGenService? activeGen;

  /// Why the last rewrite left the profile as it was, in plain words.
  String? error;

  /// "Re-read from the profile" is running, and its run.
  bool rereadingFacts = false;
  CharacterGenService? factsGen;
  String? factsError;

  /// Phase B is running (Next on the Profile step).
  bool continuing = false;

  /// The rewrite's line of direction. Grows with its text.
  final steer = TextEditingController();

  /// The interview transcript row is open.
  bool transcriptOpen = false;

  /// Back and Next wait while any of these model calls is out.
  bool get busy => rewriting || rereadingFacts || continuing;

  /// The profile reads differently from the one [recipe]'s greetings were
  /// written from. An empty stamp (Enhance, an older card) means unknown,
  /// and unknown never raises the hint. Derived from the text, never from
  /// the action that changed it, so a hand edit counts too.
  bool profileChangedSince(
    String description,
    String personality,
    GreetingRecipe recipe, {
    String name = '',
  }) {
    final stamp = recipe.profileFingerprint;
    if (stamp.isEmpty) return false;
    return profileFingerprintOf(description, personality, name: name) != stamp;
  }

  /// The name the profile fingerprint is taken with: the one Phase B
  /// stamped its greetings with.
  String fingerprintName(String cardName) => paused?.inputs.name ?? cardName;

  /// A new generation (or Start over): stop what is out and forget the
  /// paused run.
  void reset() {
    stopAll();
    paused = null;
    completed = false;
    facts = null;
    error = null;
    factsError = null;
    steer.clear();
    transcriptOpen = false;
  }

  /// Cancel whatever is out. Nothing it would have written lands.
  void stopAll() {
    activeGen?.abort();
    activeGen = null;
    rewriting = false;
    stream = const ProfileStreamView();
    factsGen?.abort();
    factsGen = null;
    rereadingFacts = false;
    continuing = false;
  }

  /// The wizard is closing.
  void dispose() {
    stopAll();
    steer.dispose();
  }
}

/// Which Review rewrite a card is running.
enum ReviewRewrite { dialogue, lorebook }

/// The Review step's two rewrites: the example dialogue and the lorebook,
/// each with its steer, its run and its error. Each locks only its own card;
/// the other card and the nav stay live (the spec's "States").
class CreatorReview {
  final dialogueSteer = TextEditingController();
  final loreSteer = TextEditingController();

  final Map<ReviewRewrite, CharacterGenService> _runs = {};
  final Map<ReviewRewrite, String> _errors = {};

  /// What the dialogue rewrite has streamed so far.
  String dialogueText = '';

  bool writing(ReviewRewrite kind) => _runs.containsKey(kind);
  CharacterGenService? runOf(ReviewRewrite kind) => _runs[kind];
  String? errorOf(ReviewRewrite kind) => _errors[kind];

  bool get busy => _runs.isNotEmpty;

  void start(ReviewRewrite kind, CharacterGenService gen) {
    _runs[kind] = gen;
    _errors.remove(kind);
    if (kind == ReviewRewrite.dialogue) dialogueText = '';
  }

  /// [gen] finished (or was stopped): drop it if it is still the live run.
  /// False when another run replaced it, so its result must not land.
  bool finish(ReviewRewrite kind, CharacterGenService gen) {
    if (!identical(_runs[kind], gen)) return false;
    _runs.remove(kind);
    if (kind == ReviewRewrite.dialogue) dialogueText = '';
    return true;
  }

  void setError(ReviewRewrite kind, String text) => _errors[kind] = text;

  /// Stop [kind]'s rewrite; its card keeps what it had.
  void stop(ReviewRewrite kind) {
    _runs.remove(kind)?.abort();
    if (kind == ReviewRewrite.dialogue) dialogueText = '';
  }

  void reset() {
    for (final kind in ReviewRewrite.values) {
      stop(kind);
    }
    _errors.clear();
    dialogueSteer.clear();
    loreSteer.clear();
  }

  void dispose() {
    for (final kind in ReviewRewrite.values) {
      stop(kind);
    }
    dialogueSteer.dispose();
    loreSteer.dispose();
  }
}
