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

import 'package:front_porch_ai/services/services.dart';

/// The Greetings step's own state (#370): which greeting is being written and
/// what has come in so far, each greeting's steer box, and the outfit hint
/// the Realism step shows after a new first message. Held by `CreatorState`,
/// which notifies; the work itself is `CreatorGreetingEngine`.
class CreatorGreetings {
  /// The most alternates the creator writes or lets you add.
  static const maxAlternates = kMaxAlternateGreetings;

  /// The greeting being written: 0 is the first message, 1 and up the
  /// alternates, and one past the last alternate while Add another writes.
  /// Null when nothing is being written.
  int? writingIndex;

  /// What the model has written so far for [writingIndex].
  String writingText = '';

  /// The run Stop cancels. Only this one: Stop never touches the others.
  CharacterGenService? activeGen;

  /// Why the last write of greeting [errorIndex] failed, in plain words.
  String? errorText;
  int? errorIndex;

  /// How creation wrote the greetings, so one more is written the same way.
  GreetingRecipe recipe = const GreetingRecipe();

  /// The first message text the outfit (Wearing / Carrying) was read from:
  /// the generated one, a re-read's, or the text "Keep this outfit" accepted.
  /// Null before a card is generated.
  String? outfitReadFrom;

  /// The first message no longer says what the outfit was read from,
  /// rewritten or edited by hand: the Realism step offers a re-read. Nothing
  /// is changed until asked.
  bool firstMessageChangedFrom(String current) {
    final from = outfitReadFrom;
    return from != null && current.trim() != from.trim();
  }

  /// The outfit re-read is running, and its run (for leaving mid-read).
  bool rereadingOutfit = false;
  CharacterGenService? outfitGen;
  String? outfitError;

  final Map<TextEditingController, TextEditingController> _steers = {};

  /// Back and Next wait while either model call is out.
  bool get busy => writingIndex != null || rereadingOutfit;

  /// The one-line steer box of the greeting that [box] edits.
  TextEditingController steerFor(TextEditingController box) =>
      _steers.putIfAbsent(box, TextEditingController.new);

  /// Drop the steer box of a greeting that is going away.
  void forgetSteer(TextEditingController box) {
    final steer = _steers.remove(box);
    if (steer != null) _disposeLater(steer);
  }

  void setError(int index, String text) {
    errorIndex = index;
    errorText = text;
  }

  void clearError() {
    errorIndex = null;
    errorText = null;
  }

  /// A new card (or Start over): stop any write or re-read, drop the steer
  /// boxes, keep [next] as the new card's recipe and [outfitFrom] as the
  /// first message its outfit was read from.
  void reset({
    GreetingRecipe next = const GreetingRecipe(),
    String? outfitFrom,
  }) {
    stopAll();
    for (final steer in _steers.values) {
      _disposeLater(steer);
    }
    _steers.clear();
    clearError();
    recipe = next;
    outfitReadFrom = outfitFrom;
    outfitError = null;
  }

  /// Cancel whatever is out. Nothing it would have written lands.
  void stopAll() {
    activeGen?.abort();
    activeGen = null;
    writingIndex = null;
    writingText = '';
    outfitGen?.abort();
    outfitGen = null;
    rereadingOutfit = false;
  }

  /// The wizard is closing.
  void dispose() {
    stopAll();
    for (final steer in _steers.values) {
      steer.dispose();
    }
    _steers.clear();
  }

  /// A box can still be on screen this frame; let it go first.
  static void _disposeLater(TextEditingController c) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
}
