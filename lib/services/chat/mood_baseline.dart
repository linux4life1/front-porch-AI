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

import 'package:front_porch_ai/services/chat/weather_engine.dart';

/// A mood the user did not cause.
///
/// THE PROBLEM THIS SOLVES. Every delta the Realism Engine produces is caused
/// by the user's message. That is coherent, and it quietly makes the user the
/// centre of the character's universe — which is the tell of a companion app
/// rather than a person. Real people arrive at a conversation already in a
/// mood you had nothing to do with.
///
/// TWO THINGS THIS IS DELIBERATELY NOT, both from the maintainer's review of
/// the first proposal, and both load-bearing:
///
/// 1. **It is never unexplained.** "They are in a mood for no reason" is
///    illegible to the user — they read it as the app being random — and it is
///    an open invitation for a small local model to invent a cause and then
///    defend it for forty turns ("I'm upset because you forgot my birthday"),
///    which the Journal would then record as fact. So every offset here is
///    DERIVED from state the app already owns and can name out loud, and it
///    carries its causes with it for display. There is no LLM call in this
///    file and nothing for a model to make up: by the time the model sees
///    anything, it is a fact, not a mood.
///
/// 2. **It never reaches the evals.** [offset] colours generation and is shown
///    to the user; it is not fed to the relationship, emotional or one-shot
///    judges and it must never touch bond or trust. Mood is not relationship —
///    if a bad night cost trust, one rough day would compound into real
///    relationship damage that the user could not undo and did not cause.
///    Keeping it out of the evals also keeps regen deterministic, since the
///    eval prompt is unchanged by it.
///
/// Pure and synchronous: every input is already computed for other reasons, so
/// this costs nothing per turn and is trivially testable.
class MoodBaseline {
  /// How the day is tilting them, -3..+3. Small ON PURPOSE — this tints, it
  /// never drives. A genuine reaction to the user has to outweigh it, or the
  /// engine's actual work stops being visible underneath it.
  final int offset;

  /// The reasons, in plain language, worst first. Shown to the user verbatim
  /// (the mood chip's tooltip, the sidebar line) so they always know which
  /// part of their mood was the user and which part was their day.
  final List<String> causes;

  const MoodBaseline({required this.offset, required this.causes});

  static const neutral = MoodBaseline(offset: 0, causes: []);

  bool get isNeutral => offset == 0 || causes.isEmpty;

  /// One line for the model and the UI, e.g.
  /// "running on empty — hasn't slept, hasn't eaten".
  String get summary {
    if (isNeutral) return '';
    final head = offset <= -3
        ? 'running on empty'
        : offset < 0
        ? 'not at their best'
        : offset >= 3
        ? 'in good form'
        : 'in decent spirits';
    return '$head — ${causes.join(', ')}';
  }

  /// The prompt fragment.
  ///
  /// Says the STATE, never the mood. "They slept badly and have not eaten" is a
  /// fact with nowhere to go; "they are in a bad mood" is a prompt to invent a
  /// reason. The closing clause is the same guardrail — in the same words —
  /// that preferences_injection.dart carries, because Likes & Dislikes hit
  /// exactly this failure mode first: without it the model treats the state as
  /// a topic and steers the scene into it.
  String get injection {
    if (isNeutral) return '';
    return '[Before this conversation started, ${causes.join(' and ')}. '
        'Let it colour their tone — shorter, warmer, more distracted as fits — '
        'but do NOT raise it as a topic or invent an incident to explain it. '
        'It is simply how their day has gone.]';
  }

  Map<String, dynamic> toJson() => {'offset': offset, 'causes': causes};

  static MoodBaseline? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final o = raw['offset'];
    final c = raw['causes'];
    if (o is! num) return null;
    return MoodBaseline(
      offset: o.toInt().clamp(-3, 3),
      causes: [
        for (final e in c is List ? c : const [])
          if (e is String && e.trim().isNotEmpty) e.trim(),
      ],
    );
  }
}

/// Derive the standing mood from state that already exists.
///
/// Every source here is something the app computed for its own reasons, so
/// this adds no cost and cannot disagree with what the user is shown
/// elsewhere. Sources are deliberately limited to STATES OF THE BODY AND THE
/// DAY — tired, hungry, cold, up too late. They were chosen because they are
/// the hardest kind of fact for a model to spin into an event: "they are tired"
/// resists becoming a grievance in a way that "they are upset" does not.
///
/// [needs] is the Needs vector (absent or empty when the simulation is off —
/// then only the clock and weather contribute, which is correct rather than
/// degraded). [timeOfDay] is the story clock's period. [weather] is null when
/// Story Weather is off.
MoodBaseline deriveMoodBaseline({
  Map<String, int> needs = const {},
  String timeOfDay = '',
  DailyWeather? weather,
}) {
  var offset = 0;
  final causes = <String>[];

  /// Needs run 0..100, low is bad. Only genuinely low values speak up: a
  /// character who is merely peckish has nothing to say about their day.
  void need(String key, int threshold, String cause, int weight) {
    final v = needs[key];
    if (v == null || v > threshold) return;
    causes.add(cause);
    offset += weight;
  }

  need('energy', 25, 'they are exhausted', -2);
  need('hunger', 25, 'they have not eaten', -1);
  need('comfort', 20, 'they ache', -1);
  need('social', 15, 'they have been alone too long', -1);
  need('hygiene', 15, 'they feel unclean', -1);

  // The small end of the range is worth as much as the large: a rested,
  // well-fed character reads as buoyant, and without this the baseline could
  // only ever be a penalty — which would make every character a bit miserable
  // on average, the opposite of the point.
  final energy = needs['energy'];
  final fun = needs['fun'];
  if (energy != null && energy >= 90 && (fun == null || fun >= 70)) {
    causes.add('they slept well');
    offset += 2;
  }

  if (timeOfDay == 'night' || timeOfDay == 'dawn') {
    causes.add('it is the middle of the night');
    offset -= 1;
  }

  if (weather != null) {
    const rough = {
      WeatherCondition.storm,
      WeatherCondition.rain,
      WeatherCondition.snow,
      WeatherCondition.fog,
    };
    if (rough.contains(weather.condition)) {
      causes.add('the weather has been miserable');
      offset -= 1;
    } else if (weather.condition == WeatherCondition.clear &&
        (weather.temp == TempBand.mild || weather.temp == TempBand.warm)) {
      causes.add('it is a beautiful day');
      offset += 1;
    }
  }

  if (causes.isEmpty) return MoodBaseline.neutral;
  return MoodBaseline(offset: offset.clamp(-3, 3), causes: causes);
}
