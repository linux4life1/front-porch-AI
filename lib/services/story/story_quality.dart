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

import 'dart:math';

import 'package:front_porch_ai/models/models.dart';

/// good = healthy, warn = worth a look, bad = should be fixed, plain = a
/// neutral count. Both surfaces colour the chip from this.
enum QualityTone { plain, good, warn, bad }

class QualityChip {
  final String label;
  final QualityTone tone;

  const QualityChip(this.label, [this.tone = QualityTone.plain]);

  Map<String, String> toJson() => {'label': label, 'tone': tone.name};
}

/// Measurements of one passage. Pure counting — no model call.
class ProseQuality {
  final int wordCount;

  /// Share of words inside quotation marks, 0–1.
  final double dialogueRatio;

  /// Standard deviation of sentence length in words; low means monotone.
  final double rhythm;
  final double sensoryPer100;
  final double adverbsPer100;
  final List<String> bannedMatches;
  final int bannedCount;

  const ProseQuality({
    this.wordCount = 0,
    this.dialogueRatio = 0,
    this.rhythm = 0,
    this.sensoryPer100 = 0,
    this.adverbsPer100 = 0,
    this.bannedMatches = const [],
    this.bannedCount = 0,
  });

  List<QualityChip> get chips {
    if (wordCount == 0) return const [];
    final dialoguePct = (dialogueRatio * 100).round();
    return [
      QualityChip('$wordCount words'),
      QualityChip(
        'Dialogue $dialoguePct%',
        dialoguePct >= 10 && dialoguePct <= 70
            ? QualityTone.good
            : QualityTone.warn,
      ),
      rhythm >= 5
          ? const QualityChip('Rhythm varied', QualityTone.good)
          : const QualityChip('Rhythm flat', QualityTone.warn),
      QualityChip(
        'Sensory ${sensoryPer100.toStringAsFixed(1)} / 100',
        sensoryPer100 >= 5 ? QualityTone.good : QualityTone.warn,
      ),
      QualityChip(
        'Adverbs ${adverbsPer100.toStringAsFixed(1)}',
        adverbsPer100 > 3 ? QualityTone.warn : QualityTone.plain,
      ),
      if (bannedCount > 0)
        QualityChip(
          '$bannedCount banned phrase${bannedCount == 1 ? '' : 's'}',
          QualityTone.bad,
        ),
    ];
  }

  Map<String, dynamic> toJson() => {
    'word_count': wordCount,
    'dialogue_ratio': dialogueRatio,
    'rhythm': rhythm,
    'sensory_per_100': sensoryPer100,
    'adverbs_per_100': adverbsPer100,
    'banned_matches': bannedMatches,
    'banned_count': bannedCount,
    'chips': chips.map((c) => c.toJson()).toList(),
  };
}

abstract final class StoryQuality {
  static final _sensory = RegExp(
    r'\b(saw|bright|dark|shadow|shadows|gleam|gleamed|glow|glowing|red|blue|green|crimson|pale|shimmer|shimmered|gaze|gazed|glimpse|glimpsed|flash|flashed|flicker|flickered|silhouette|silhouettes|blur|blurred|glare|sparkle|sparkled|dim|vivid|golden|silver|amber|onyx|emerald|obsidian|iridescent|radiant|transparent|murky|pitch|neon|sound|sounded|hear|heard|murmur|murmured|whisper|whispered|echo|echoed|hum|humming|roar|roared|hiss|hissed|clang|clanged|scream|screamed|shriek|shrieked|rattle|rattled|snap|snapped|crackle|crackled|buzz|buzzing|chime|chimed|thump|thumped|clatter|clattered|rustle|rustled|rumble|rumbled|deafening|screech|creak|creaked|ring|ringing|raspy|acoustic|resonance|smell|smelled|scent|scented|odor|aroma|fragrance|stench|musk|musky|metallic|ozone|acrid|stale|perfume|pungent|foul|floral|damp|smokey|smoke|sulfur|vinegar|citrus|sweet|sour|putrid|rotten|taste|tasted|bitter|salty|savory|tangy|copper|acid|iron|burnt|scorch|scorched|spicy|astringent|bile|blood|nectar|ash|touch|touched|feel|feeling|cold|warm|hot|icy|burning|smooth|rough|coarse|sharp|soft|hard|wet|dry|pressure|prickle|prickled|numb|sting|stung|tingle|tingled|grit|gritty|sticky|slick|greasy|heavy|shivering|pulse|pulsing|vibration|friction|grain)\b',
    caseSensitive: false,
  );

  // Word lists are space-separated strings so the formatter cannot explode
  // them to one word per line.
  static final _notAdverbs =
      ('only early family friendly daily lonely holy ugly deadly lively '
              'likely unlikely anomaly ally belly rally bully supply apply '
              'imply reply rely fly jelly lily folly silly curly chilly '
              'orderly elderly monopoly assembly butterfly dragonfly gravelly '
              'pebbly crinkly wrinkly bristly steely wooly oily italy july '
              'holly molly sally billy emily lovely')
          .split(' ')
          .toSet();

  static final _stopWords =
      ('the be to of and a in that have i it for not on with he as you do at '
              'this but his by from they we say her she or an will my one all '
              'would there their what so up out if about who get which go me '
              'when make can like time no just him know take into your some '
              'could them see other than then now look only come its over '
              'think also back after use two how our first well way even new '
              'want because any these give most us said asked was were had '
              'been are is am has did does got very too again once before '
              'until while where why here down off through toward towards '
              "against between under across without within didn't don't "
              "wasn't couldn't wouldn't hadn't it's")
          .split(' ')
          .toSet();

  static List<String> _words(String text) =>
      text.trim().split(RegExp(r'\s+'))..removeWhere((w) => w.isEmpty);

  static ProseQuality analyze(
    String prose, {
    List<String> bannedPhrases = const [],
  }) {
    final words = _words(prose);
    if (words.isEmpty) return const ProseQuality();
    final count = words.length;

    var dialogueWords = 0;
    for (final m in RegExp('"([^"]*)"|“([^”]*)”').allMatches(prose)) {
      dialogueWords += _words(m.group(1) ?? m.group(2) ?? '').length;
    }

    final lengths = prose
        .split(RegExp(r'(?<=[.!?]["”]?)\s+'))
        .map((s) => _words(s).length)
        .where((n) => n > 0)
        .toList();
    var rhythm = 0.0;
    if (lengths.length > 1) {
      final mean = lengths.reduce((a, b) => a + b) / lengths.length;
      final variance =
          lengths.fold<double>(0, (v, n) => v + pow(n - mean, 2)) /
          lengths.length;
      rhythm = sqrt(variance);
    }

    final adverbs = RegExp(r'\b[a-zA-Z]+ly\b')
        .allMatches(prose)
        .where((m) => !_notAdverbs.contains(m.group(0)!.toLowerCase()))
        .length;

    final lower = prose.toLowerCase();
    var bannedCount = 0;
    final matches = <String>[];
    for (final phrase in bannedPhrases) {
      final p = phrase.trim().toLowerCase();
      if (p.isEmpty) continue;
      final hits = RegExp(
        '(?<![a-z])${RegExp.escape(p)}(?![a-z])',
      ).allMatches(lower).length;
      if (hits > 0) {
        bannedCount += hits;
        matches.add(p);
      }
    }

    double per100(int n) => n / (count / 100);
    return ProseQuality(
      wordCount: count,
      dialogueRatio: dialogueWords / count,
      rhythm: rhythm,
      sensoryPer100: per100(_sensory.allMatches(prose).length),
      adverbsPer100: per100(adverbs),
      bannedMatches: matches,
      bannedCount: bannedCount,
    );
  }

  /// Phrases the model has started leaning on: 2–4 word runs that recur at
  /// least [threshold] times in [recentProse]. Names in [exclude] (the cast)
  /// are never banned, and a short run already covered by a longer one that
  /// recurs as often is dropped so the list is not three views of one tic.
  static List<String> overusedPhrases(
    String recentProse, {
    Iterable<String> exclude = const [],
    int threshold = 3,
    int limit = 12,
  }) {
    final excluded = {
      for (final e in exclude)
        for (final part in e.toLowerCase().split(RegExp(r'\s+')))
          if (part.isNotEmpty) part,
    };
    final words = recentProse
        .toLowerCase()
        .replaceAll(RegExp("[^a-z0-9'\\s]"), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final counts = <String, int>{};
    for (var size = 2; size <= 4; size++) {
      for (var i = 0; i + size <= words.length; i++) {
        final gram = words.sublist(i, i + size);
        if (gram.any(excluded.contains)) continue;
        if (gram.every(_stopWords.contains)) continue;
        if (_stopWords.contains(gram.first) && _stopWords.contains(gram.last)) {
          continue;
        }
        final key = gram.join(' ');
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    final repeated = counts.entries.where((e) => e.value >= threshold).toList()
      ..sort((a, b) {
        final byLength = b.key.length.compareTo(a.key.length);
        return byLength != 0 ? byLength : b.value.compareTo(a.value);
      });
    final kept = <MapEntry<String, int>>[];
    for (final e in repeated) {
      final covered = kept.any(
        (k) => k.key.contains(e.key) && k.value >= e.value - 1,
      );
      if (!covered) kept.add(e);
    }
    kept.sort((a, b) => b.value.compareTo(a.value));
    return kept.take(limit).map((e) => e.key).toList();
  }

  /// Prose from the scenes just before ([act], [scene]) — the window the
  /// rolling ban list is computed from.
  static String recentProse(
    StoryProject project,
    int act,
    int scene, {
    int scenesBack = 4,
  }) {
    final before = project.orderedScenes
        .takeWhile((r) => !(r.act == act && r.index == scene))
        .toList();
    return before.reversed
        .take(scenesBack)
        .map((r) => project.sceneText(r.act, r.index))
        .where((t) => t.isNotEmpty)
        .join('\n\n');
  }
}
