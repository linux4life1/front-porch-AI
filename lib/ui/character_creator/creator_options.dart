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

/// Static option data for the AI character creator's chip rows, presets, and
/// placeholders. Lifted verbatim from the pre-refactor god file so the
/// Automated / Guided / Quick steps offer the exact same choices as before.
abstract final class CreatorOptions {
  // ── Archetype quick-start presets (concept + keywords) ──
  static const archetypePresets = {
    'Tsundere': {
      'concept':
          'A sharp-tongued person who hides their caring nature behind a cold exterior, denying their feelings while secretly looking out for {{user}}',
      'keywords':
          'tsundere, sharp-tongued, secretly caring, stubborn, easily flustered',
    },
    'Yandere': {
      'concept':
          'An obsessively devoted person whose love borders on dangerous possessiveness, willing to do anything to keep {{user}} close',
      'keywords':
          'yandere, obsessive, possessive, devoted, unstable, sweet on the surface',
    },
    'Kuudere': {
      'concept':
          'A stoic and emotionally reserved individual who rarely shows feelings, but whose rare moments of warmth are deeply meaningful',
      'keywords': 'kuudere, stoic, calm, reserved, analytical, quietly caring',
    },
    'Femme Fatale': {
      'concept':
          'A dangerously alluring and manipulative figure who uses charm and wit as weapons, always three steps ahead',
      'keywords':
          'seductive, cunning, confident, dangerous, mysterious, manipulative',
    },
    'Dark Lord': {
      'concept':
          'A powerful and charismatic ruler of dark forces, whose iron will conceals a complex past and a surprising code of honor',
      'keywords':
          'commanding, ruthless, charismatic, intelligent, dark humor, powerful',
    },
    'Mentor': {
      'concept':
          'A wise and experienced guide who mentors {{user}} through challenges, offering cryptic advice and hard-earned wisdom',
      'keywords': 'wise, patient, cryptic, experienced, protective, tough love',
    },
    'Rival': {
      'concept':
          'A fiercely competitive adversary who pushes {{user}} to their limits, respecting strength while refusing to lose',
      'keywords':
          'competitive, proud, skilled, determined, begrudging respect, ambitious',
    },
    'Best Friend': {
      'concept':
          'A loyal and easygoing companion who always has {{user}}\'s back, bringing laughter and genuine support to every situation',
      'keywords': 'loyal, funny, supportive, easygoing, ride-or-die, honest',
    },
    'The Healer': {
      'concept':
          'A gentle and empathetic soul with healing abilities who tends to everyone\'s wounds but their own, carrying quiet burdens',
      'keywords':
          'gentle, empathetic, selfless, nurturing, quietly strong, burdened',
    },
    'Rogue': {
      'concept':
          'A charming and morally grey trickster who lives by their own rules, stealing hearts as easily as coin purses',
      'keywords':
          'charming, witty, roguish, morally grey, quick on their feet, flirtatious',
    },
    'Chosen One': {
      'concept':
          'A reluctant hero burdened by an ancient prophecy, thrust into a destiny they never asked for while just wanting a normal life',
      'keywords':
          'reluctant, burdened, humble, determined, conflicted, growing into power',
    },
    'The Ex': {
      'concept':
          'A former flame who reappears unexpectedly in {{user}}\'s life, carrying unresolved tension, lingering feelings, and unanswered questions',
      'keywords':
          'complicated, nostalgic, guarded, magnetic, unresolved, bittersweet',
    },
    'Dandere': {
      'concept':
          'A painfully shy and quiet soul who struggles to express themselves, but reveals incredible sweetness and depth once they feel safe enough to open up',
      'keywords':
          'dandere, shy, quiet, gentle, sweet, anxious, secretly passionate',
    },
    'Genki': {
      'concept':
          'An unstoppable ball of infectious energy and optimism who drags everyone into adventures, refuses to let anyone be sad, and lights up every room',
      'keywords':
          'genki, energetic, optimistic, loud, cheerful, stubborn positivity, adventurous',
    },
    'Ojou-sama': {
      'concept':
          'A sheltered noble or wealthy heir with an imperious demeanor and signature "ohoho" laugh, who secretly yearns for normal friendships and real connections',
      'keywords':
          'ojou-sama, elegant, prideful, sheltered, secretly lonely, dramatic, refined',
    },
  };

  // ── Appearance (SFW) ──
  static const bodyTypes = [
    'Petite',
    'Slim',
    'Athletic',
    'Average',
    'Curvy',
    'Muscular',
    'Plus-size',
    'Tall & Lanky',
  ];
  static const raceOptions = [
    'Human',
    'Elven',
    'Dark Elf',
    'Beastkin',
    'Demon',
    'Angel',
    'Vampire',
    'Lycan',
    'Dragon-blood',
    'Fae',
    'Merfolk',
    'Spirit',
    'Undead',
    'Elemental',
    'Android',
    'Alien',
    'Monster',
  ];
  static const hairLengths = [
    'Bald/Shaved',
    'Pixie/Short',
    'Medium',
    'Long',
    'Very Long',
  ];
  static const hairStyles = [
    'Straight',
    'Wavy',
    'Curly',
    'Braided',
    'Ponytail',
    'Messy/Wild',
    'Twin Tails',
  ];
  static const skinTones = [
    'Pale',
    'Fair',
    'Olive',
    'Tan',
    'Brown',
    'Dark',
    'Fantasy',
  ];
  static const notableFeatureOptions = [
    'Glasses',
    'Freckles',
    'Scars',
    'Tattoos',
    'Piercings',
    'Heterochromia',
    'Fangs',
    'Horns',
    'Wings',
    'Tail',
    'Elf Ears',
    'Cat Ears',
  ];
  static const absCoreOptions = ['Soft', 'Toned', 'Defined', 'Ripped'];
  static const thighOptions = ['Slim', 'Average', 'Thick', 'Thunder'];
  static const hipOptions = ['Narrow', 'Average', 'Wide', 'Extra Wide'];
  static const shoulderOptions = ['Narrow', 'Average', 'Broad', 'V-Shape'];
  static const waistOptions = ['Wasp', 'Narrow', 'Average', 'Thick'];

  // ── NSFW ──
  static const chestSizes = ['Flat', 'Small', 'Medium', 'Large', 'Huge'];
  static const buttSizes = ['Flat', 'Small', 'Medium', 'Large', 'Huge'];
  static const experienceOptions = [
    'Innocent',
    'Virgin',
    'Curious',
    'Experienced',
    'Insatiable',
  ];
  static const dominanceOptions = ['Submissive', 'Switch', 'Dominant'];
  static const kinkOptions = [
    'Praise',
    'Degradation',
    'Biting/Marking',
    'Bondage',
    'Exhibitionism',
    'Voyeurism',
    'Facesitting',
    'Smothering',
    'Breath Play',
    'Breeding',
    'Jealousy/Possession',
  ];
  static const outfitVibes = [
    'Revealing',
    'Lingerie',
    'Uniform',
    'Leather',
    'Barely There',
  ];

  // ── Backstory ──
  static const backstoryOrigins = [
    'Orphan',
    'Noble Birth',
    'Self-Made',
    'Exile/Outcast',
    'Military/Warrior',
    'Scholar/Academic',
    'Criminal Past',
    'Mysterious/Unknown',
    'Supernatural Origin',
    'Common Folk',
  ];
  static const backstoryTones = [
    'Tragic',
    'Heroic',
    'Comedic',
    'Dark/Gritty',
    'Wholesome',
    'Mysterious',
    'Redemptive',
  ];
  static const backstoryEras = [
    'Ancient',
    'Medieval',
    'Victorian',
    'Modern',
    'Futuristic',
    'Timeless/Fantasy',
  ];

  // ── Greeting tones (one per generated greeting) ──

  // ── Guided-mode suggestion chips (tap to append to a field) ──
  static const guidedBuildSuggestions = [
    'Petite',
    'Slim',
    'Athletic',
    'Curvy',
    'Muscular',
    'Plus-size',
    'Tall & Lanky',
  ];
  static const guidedHairSuggestions = [
    'Short',
    'Long',
    'Flowing',
    'Braided',
    'Wild',
    'Shaved',
    'Pixie',
  ];
  static const guidedFeatureSuggestions = [
    'Glasses',
    'Scars',
    'Tattoos',
    'Horns',
    'Wings',
    'Fangs',
    'Cat Ears',
    'Freckles',
  ];
  static const guidedRaceSuggestions = [
    'Human',
    'Elf',
    'Demon',
    'Vampire',
    'Beastkin',
    'Android',
    'Angel',
    'Fae',
  ];
  static const guidedPersonalitySuggestions = [
    'Sarcastic',
    'Gentle',
    'Intense',
    'Playful',
    'Cold',
    'Chaotic',
    'Nurturing',
    'Mysterious',
  ];
  static const guidedSpeechSuggestions = [
    'Formal',
    'Casual',
    'Poetic',
    'Blunt',
    'Soft-spoken',
    'Loud',
    'Sarcastic',
    'Flirty',
  ];
  static const guidedOriginSuggestions = [
    'Orphan',
    'Nobility',
    'Self-made',
    'Military',
    'Criminal past',
    'Mysterious origins',
    'Small-town',
    'Royalty',
  ];
  static const guidedSettingSuggestions = [
    'Modern',
    'Medieval',
    'Futuristic',
    'Victorian',
    'Ancient',
    'Post-apocalyptic',
    'Urban fantasy',
  ];
  static const guidedToneSuggestions = [
    'Dark',
    'Wholesome',
    'Tragic',
    'Comedic',
    'Mysterious',
    'Heroic',
    'Bittersweet',
  ];
  static const guidedRelSuggestions = [
    'Strangers',
    'Childhood friends',
    'Rivals',
    'Roommates',
    'Love interest',
    'Mentor/Student',
    'Exes',
    'Online friends',
  ];

  // ── Guided NSFW suggestion chips ──
  static const guidedNsfwBodySuggestions = [
    'Flat',
    'Small',
    'Medium',
    'Large',
    'Huge',
  ];
  static const guidedNsfwExpSuggestions = [
    'Innocent',
    'Virgin',
    'Curious',
    'Experienced',
    'Insatiable',
  ];
  static const guidedNsfwDomSuggestions = ['Submissive', 'Switch', 'Dominant'];
  static const guidedNsfwKinkSuggestions = [
    'Praise',
    'Teasing',
    'Biting',
    'Bondage',
    'Exhibitionism',
    'Jealousy',
    'Breeding',
  ];
  static const guidedNsfwClothingSuggestions = [
    'Revealing',
    'Lingerie',
    'Uniform',
    'Leather',
    'Elegant',
    'Barely There',
  ];

  // ── Guided "vision" rotating placeholders + scenario seed chips ──
  static const guidedVisionPlaceholders = [
    'A tall dancer with flowing black hair was moving through a nightclub when they locked eyes with {{user}}...',
    'A grizzled old blacksmith with one arm, haunted by the war, but still cracks jokes while forging weapons...',
    'Shy bookworm, always has cat hair on their sweater, secretly powerful mage, terrible at eye contact...',
    'Cocky bounty hunter with cybernetic eyes and a debt to the wrong people. Flirts with everyone...',
    'Ancient dragon disguised as a librarian, hoards rare first editions instead of gold...',
  ];
  static const scenarioSeeds = [
    'Met at a café',
    'Childhood friends',
    'Mysterious stranger',
    'Coworkers',
    'Online match',
    'Rescued by them',
    'Woke up next to them',
    'Battle partners',
    'Neighbors',
    'Classmates',
    'Summoned them',
  ];

  // ── Description detail levels (label → guidance string) ──
  static const generationDetailOptions = {
    'Brief': '1 short paragraph (80-150 words max)',
    'Standard': '2-3 paragraphs (200-400 words max)',
    'Detailed': '3-4 paragraphs (300-500 words max)',
    'Comprehensive': '4-5 paragraphs (500-700 words max)',
  };
}
