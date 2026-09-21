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

part of 'needs_impact_evaluator.dart';

/// Simple keyword-based fallback for scenes where the model returns
/// all-zero or empty deltas. Scans for activity keywords and assigns
/// reasonable positive deltas so the character doesn't stagnate.
Map<String, int> needsImpactAfkKeywordFallback(String sceneText) {
  final text = sceneText.toLowerCase();
  final result = <String, int>{};

  bool matchesWordBoundary(Iterable<String> keywords, String text) {
    return keywords.any((k) {
      return RegExp('\\b${RegExp.escape(k)}\\b').hasMatch(text);
    });
  }

  void check(Iterable<String> keywords, Map<String, int> deltas) {
    if (matchesWordBoundary(keywords, text)) {
      for (final entry in deltas.entries) {
        final existing = result[entry.key] ?? 0;
        if (entry.value > existing) {
          result[entry.key] = entry.value;
        }
      }
    }
  }

  // Bladder
  check(
    [
      'toilet',
      'bathroom',
      'urinate',
      'peed',
      'peeing',
      'used the bathroom',
      'went to the bathroom',
      'en suite',
    ],
    {'bladder': 50},
  );

  // Hygiene — specific phrases first
  check(
    ['shower', 'showering', 'showered', 'showers', 'bath', 'bathed', 'bathing'],
    {'hygiene': 40, 'comfort': 10},
  );
  check(
    [
      'washed her face',
      'washed his face',
      'washed their face',
      'washed up',
      'washed herself',
      'washed himself',
      'washed themselves',
      'dish',
      'brushed her teeth',
      'brushed his teeth',
      'brushed their teeth',
      'brushing her teeth',
      'brushing his teeth',
      'brushing their teeth',
    ],
    {'hygiene': 20},
  );
  check(
    [
      'splashed water on her face',
      'splashed water on his face',
      'splashed water on their face',
      'splashed some water',
      'freshened up',
      'freshening up',
    ],
    {'hygiene': 15},
  );
  check(['washed', 'washing'], {'hygiene': 25});
  check(
    [
      'changed clothes',
      'changed into',
      'got dressed',
      'pajamas',
      'clean clothes',
      'comfy clothes',
    ],
    {'hygiene': 10},
  );

  // Hunger
  check(
    [
      'ate',
      'eating',
      'had breakfast',
      'had lunch',
      'had dinner',
      'dinner',
      'made breakfast',
      'made lunch',
      'made dinner',
    ],
    {'hunger': 35},
  );
  check(
    [
      'food',
      'foods',
      'meal',
      'pizza',
      'leftovers',
      'leftover',
      'pasta',
      'sandwich',
      'snack',
      'popcorn',
      'cereal',
      'apple',
      'cheese',
      'toast',
      'cooking',
      'browsing recipes',
      'recipe',
      'groceries',
      'takeout',
    ],
    {'hunger': 25},
  );
  check(
    [
      'fridge',
      'refrigerator',
      'microwave',
      'kitchen',
      'making food',
      'preparing food',
    ],
    {'hunger': 10},
  );

  // Beverages → energy (not hunger)
  check(
    [
      'coffee',
      'tea',
      'orange juice',
      'juice',
      'water',
      'soda',
      'beverage',
      'mug',
      'cup of',
      'fresh pot',
      'brew',
    ],
    {'energy': 7},
  );

  // Energy
  check(
    ['slept', 'sleeping', 'asleep', 'fell asleep', 'went to sleep', 'sleep'],
    {'energy': 50},
  );
  check(
    ['nap', 'napping', 'dozed', 'dozing', 'dozed off', 'drifted off'],
    {'energy': 25},
  );
  check(
    [
      'rested',
      'resting',
      'lay down',
      'lying down',
      'stretched out',
      'curled up',
      'lounging',
    ],
    {'energy': 15},
  );
  check(['stretch', 'stretching', 'yawned', 'yawning'], {'energy': 5});

  // Comfort
  check(
    [
      'book',
      'books',
      'reading',
      'reads',
      'read a',
      'novel',
      'magazine',
      'page',
      'chapter',
      'story',
    ],
    {'comfort': 20},
  );
  check(
    [
      'tv',
      'television',
      'movie',
      'show',
      'shows',
      'watching',
      'video',
      'netflix',
      'streaming',
    ],
    {'comfort': 10},
  );
  check(
    [
      'photo',
      'album',
      'memento',
      'photograph',
      'pictures',
      'memories',
      'scrapbook',
    ],
    {'comfort': 15},
  );
  check(
    [
      'couch',
      'sofa',
      'bed',
      'comfortable',
      'cozy',
      'warm',
      'peaceful',
      'relaxed',
      'content',
      'serene',
    ],
    {'comfort': 10},
  );
  check(
    [
      'sunlight',
      'morning sun',
      'golden light',
      'dappled',
      'nice view',
      'backyard',
      'birds singing',
      'garden',
    ],
    {'comfort': 8},
  );
  check(
    ['candle', 'music', 'quiet', 'rain', 'fireplace', 'calm', 'tranquil'],
    {'comfort': 10},
  );

  // Fun
  check(
    [
      'phone',
      'computer',
      'laptop',
      'social media',
      'scrolling',
      'instagram',
      'facebook',
      'browsing',
      'online',
      'website',
      'surfing',
    ],
    {'fun': 8},
  );
  check(
    [
      'game',
      'gaming',
      'played',
      'hobby',
      'craft',
      'drawing',
      'music',
      'instrument',
    ],
    {'fun': 15},
  );

  // Social
  check(
    [
      'friend',
      'friends',
      'neighbor',
      'neighbors',
      'talked to',
      'chatting with',
      'texted',
      'called',
      'phone call',
      'messaged',
    ],
    {'social': 15},
  );

  return result;
}
