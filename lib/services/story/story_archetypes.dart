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

/// Random story concept archetypes offered to the user on the Concept step
/// of the Porch Stories wizard (genre / style / one-line concept). Extracted
/// verbatim from `story_pipeline_service.dart` (Cluster C of the god-file
/// split) — pure and static, zero pipeline state.
abstract final class StoryArchetypes {
  static const _genres = [
    "Space Opera",
    "Cyberpunk",
    "High Fantasy",
    "Urban Fantasy",
    "Post-Apocalyptic",
    "Dystopian",
    "Gothic Horror",
    "Cosmic Horror",
    "Hard Boiled Noir",
    "Western",
    "Steampunk",
    "Romantic Comedy",
    "Political Thriller",
    "Espionage",
    "Superhero",
    "Slice of Life",
    "Historical Drama",
    "Military Sci-Fi",
    "Whodunit",
    "Survival Thriller",
  ];

  static const _styles = [
    "Moody & Atmospheric",
    "Fast-paced & Kinetic",
    "Witty & Satirical",
    "Dark & Gritty",
    "Optimistic & Whimsical",
    "Intellectual & Philosophical",
    "Minimalist & Stark",
    "Lyrical & Poetic",
    "Suspenseful & Tense",
    "Melancholic & Reflective",
    "Campy & Over-the-top",
    "Brutal & Unflinching",
  ];

  static const _concepts = [
    "a lone wanderer seeks redemption for a past sin",
    "a team of specialists pulls off the ultimate heist",
    "a detective investigates a murder that shouldn't be possible",
    "strangers are trapped together in a confined location",
    "a chosen one rejects their destiny",
    "an artificial intelligence discovers emotions",
    "a magical artifact ruins the life of its owner",
    "two enemies are forced to work together to survive",
    "a civilization faces imminent collapse from an unseen threat",
    "a character wakes up with no memory in a strange world",
    "a forbidden romance alters the course of history",
    "a small lie spirals out of control into a global conspiracy",
    "an explorer discovers a land that defies the laws of physics",
    "a soldier questions the morality of their orders",
    "a family secret threatens to destroy a dynasty",
    "a scientist's experiment goes horribly wrong",
    "an underdog competes in a high-stakes tournament",
    "a ghost tries to solve their own murder",
    "a time traveler tries to fix a mistake but makes it worse",
    "a peaceful community is invaded by a superior force",
  ];

  /// Generate random story concept archetypes for the user to choose from.
  static List<Map<String, String>> generate({int count = 10}) {
    final options = <Map<String, String>>[];
    final rng = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < count; i++) {
      final genre = _genres[(rng + i * 7) % _genres.length];
      final style = _styles[(rng + i * 13) % _styles.length];
      final concept = _concepts[(rng + i * 3) % _concepts.length];
      options.add({
        'label': '$genre / $style / ${concept.substring(0, 30)}...',
        // The spark chip on the Idea step: the premise alone, capitalised.
        'spark': concept[0].toUpperCase() + concept.substring(1),
        'value': 'A $genre story written in a $style style, wherein $concept.',
      });
    }
    return options;
  }
}
