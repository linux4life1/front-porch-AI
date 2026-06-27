// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure data + assembly for the AI character creator's three modes (Quick /
// Guided / Automated). The generator itself is headless and shared; these
// functions only marshal the wizard's fields into the concept / characterContext
// / backstory strings the desktop creator_state_engine builds, so a web-created
// character matches a desktop-created one 1:1. Option lists are ported verbatim
// from lib/ui/character_creator/creator_options.dart + creator_state.dart.

export type ChargenMode = 'quick' | 'guided' | 'automated';

export interface ChargenForm {
  name: string;
  mode: ChargenMode;
  nsfw: boolean;
  age: string;
  sex: string;
  worldLore: string; // scraped/attached lore context fed to generation
  // Shared output settings
  greetingLength: string;
  altGreetingCount: number;
  greetingTones: string[];
  generateLorebook: boolean;
  loreCategories: string[];
  loreDepth: string;
  generationDetail: string; // label key into GENERATION_DETAIL
  // Quick
  quickConcept: string;
  quickKeywords: string;
  quickScenario: string;
  // Guided
  vision: string;
  gBuild: string;
  gHair: string;
  gFeatures: string;
  gRace: string;
  gPersonality: string;
  gSpeech: string;
  gSecret: string;
  gOrigin: string;
  gSetting: string;
  gTone: string;
  gRel: string;
  gRelScenario: string;
  gnBody: string;
  gnExp: string;
  gnDom: string;
  gnKinks: string;
  gnClothing: string;
  gnPersonality: string;
  // Automated
  aConcept: string;
  aKeywords: string;
  race: string;
  customRace: string;
  bodyType: string;
  hairLength: string;
  hairStyle: string;
  skinTone: string;
  notableFeatures: string[];
  absCore: string;
  thighs: string;
  hips: string;
  shoulders: string;
  waist: string;
  chestSize: string;
  buttSize: string;
  experience: string;
  dominance: string;
  kinks: string[];
  customKinks: string;
  outfitVibe: string;
  backstoryOrigin: string;
  backstoryTone: string;
  backstoryEra: string;
  backstoryNotes: string;
  relationships: string[];
  customRelationship: string;
}

export const DEFAULT_FORM: ChargenForm = {
  name: '',
  mode: 'quick',
  nsfw: false,
  age: '',
  sex: '',
  worldLore: '',
  greetingLength: 'Medium (2-4 paragraphs)',
  altGreetingCount: 2,
  greetingTones: ['Neutral'],
  generateLorebook: true,
  loreCategories: [],
  loreDepth: 'Standard',
  generationDetail: 'Standard',
  quickConcept: '',
  quickKeywords: '',
  quickScenario: '',
  vision: '',
  gBuild: '',
  gHair: '',
  gFeatures: '',
  gRace: '',
  gPersonality: '',
  gSpeech: '',
  gSecret: '',
  gOrigin: '',
  gSetting: '',
  gTone: '',
  gRel: '',
  gRelScenario: '',
  gnBody: '',
  gnExp: '',
  gnDom: '',
  gnKinks: '',
  gnClothing: '',
  gnPersonality: '',
  aConcept: '',
  aKeywords: '',
  race: '',
  customRace: '',
  bodyType: '',
  hairLength: '',
  hairStyle: '',
  skinTone: '',
  notableFeatures: [],
  absCore: '',
  thighs: '',
  hips: '',
  shoulders: '',
  waist: '',
  chestSize: '',
  buttSize: '',
  experience: '',
  dominance: '',
  kinks: [],
  customKinks: '',
  outfitVibe: '',
  backstoryOrigin: '',
  backstoryTone: '',
  backstoryEra: '',
  backstoryNotes: '',
  relationships: [],
  customRelationship: '',
};

// ── Option lists (verbatim from creator_options.dart / creator_state.dart) ──

export const GREETING_LENGTHS = [
  'Short (1-2 paragraphs)',
  'Medium (2-4 paragraphs)',
  'Long (4-6 paragraphs)',
];
export const TONE_OPTIONS = [
  'Neutral', 'Friendly', 'Mysterious', 'Aggressive', 'Playful',
  'Serious', 'Flirty', 'Cold', 'Nervous',
];
export const LORE_CATEGORIES = [
  'Locations', 'NPCs/Allies', 'Factions/Organizations', 'Culture/Customs',
  'Abilities/Magic', 'Flora/Fauna', 'Items/Equipment', 'History/Events',
  'Secrets/Hidden Lore',
];
export const LORE_DEPTHS = ['Light', 'Standard', 'Deep'];
export const GENERATION_DETAIL: Record<string, string> = {
  Brief: '1 short paragraph (80-150 words max)',
  Standard: '2-3 paragraphs (200-400 words max)',
  Detailed: '3-4 paragraphs (300-500 words max)',
  Comprehensive: '4-5 paragraphs (500-700 words max)',
};

export const ARCHETYPES: Record<string, { concept: string; keywords: string }> = {
  Tsundere: { concept: 'A sharp-tongued person who hides their caring nature behind a cold exterior, denying their feelings while secretly looking out for {{user}}', keywords: 'tsundere, sharp-tongued, secretly caring, stubborn, easily flustered' },
  Yandere: { concept: 'An obsessively devoted person whose love borders on dangerous possessiveness, willing to do anything to keep {{user}} close', keywords: 'yandere, obsessive, possessive, devoted, unstable, sweet on the surface' },
  Kuudere: { concept: 'A stoic and emotionally reserved individual who rarely shows feelings, but whose rare moments of warmth are deeply meaningful', keywords: 'kuudere, stoic, calm, reserved, analytical, quietly caring' },
  'Femme Fatale': { concept: 'A dangerously alluring and manipulative figure who uses charm and wit as weapons, always three steps ahead', keywords: 'seductive, cunning, confident, dangerous, mysterious, manipulative' },
  'Dark Lord': { concept: 'A powerful and charismatic ruler of dark forces, whose iron will conceals a complex past and a surprising code of honor', keywords: 'commanding, ruthless, charismatic, intelligent, dark humor, powerful' },
  Mentor: { concept: 'A wise and experienced guide who mentors {{user}} through challenges, offering cryptic advice and hard-earned wisdom', keywords: 'wise, patient, cryptic, experienced, protective, tough love' },
  Rival: { concept: 'A fiercely competitive adversary who pushes {{user}} to their limits, respecting strength while refusing to lose', keywords: 'competitive, proud, skilled, determined, begrudging respect, ambitious' },
  'Best Friend': { concept: "A loyal and easygoing companion who always has {{user}}'s back, bringing laughter and genuine support to every situation", keywords: 'loyal, funny, supportive, easygoing, ride-or-die, honest' },
  'The Healer': { concept: "A gentle and empathetic soul with healing abilities who tends to everyone's wounds but their own, carrying quiet burdens", keywords: 'gentle, empathetic, selfless, nurturing, quietly strong, burdened' },
  Rogue: { concept: 'A charming and morally grey trickster who lives by their own rules, stealing hearts as easily as coin purses', keywords: 'charming, witty, roguish, morally grey, quick on their feet, flirtatious' },
  'Chosen One': { concept: 'A reluctant hero burdened by an ancient prophecy, thrust into a destiny they never asked for while just wanting a normal life', keywords: 'reluctant, burdened, humble, determined, conflicted, growing into power' },
  'The Ex': { concept: "A former flame who reappears unexpectedly in {{user}}'s life, carrying unresolved tension, lingering feelings, and unanswered questions", keywords: 'complicated, nostalgic, guarded, magnetic, unresolved, bittersweet' },
  Dandere: { concept: 'A painfully shy and quiet soul who struggles to express themselves, but reveals incredible sweetness and depth once they feel safe enough to open up', keywords: 'dandere, shy, quiet, gentle, sweet, anxious, secretly passionate' },
  Genki: { concept: 'An unstoppable ball of infectious energy and optimism who drags everyone into adventures, refuses to let anyone be sad, and lights up every room', keywords: 'genki, energetic, optimistic, loud, cheerful, stubborn positivity, adventurous' },
  'Ojou-sama': { concept: 'A sheltered noble or wealthy heir with an imperious demeanor and signature "ohoho" laugh, who secretly yearns for normal friendships and real connections', keywords: 'ojou-sama, elegant, prideful, sheltered, secretly lonely, dramatic, refined' },
};

export const BODY_TYPES = ['Petite', 'Slim', 'Athletic', 'Average', 'Curvy', 'Muscular', 'Plus-size', 'Tall & Lanky'];
export const RACE_OPTIONS = ['Human', 'Elven', 'Dark Elf', 'Beastkin', 'Demon', 'Angel', 'Vampire', 'Lycan', 'Dragon-blood', 'Fae', 'Merfolk', 'Spirit', 'Undead', 'Elemental', 'Android', 'Alien', 'Monster'];
export const HAIR_LENGTHS = ['Bald/Shaved', 'Pixie/Short', 'Medium', 'Long', 'Very Long'];
export const HAIR_STYLES = ['Straight', 'Wavy', 'Curly', 'Braided', 'Ponytail', 'Messy/Wild', 'Twin Tails'];
export const SKIN_TONES = ['Pale', 'Fair', 'Olive', 'Tan', 'Brown', 'Dark', 'Fantasy'];
export const NOTABLE_FEATURES = ['Glasses', 'Freckles', 'Scars', 'Tattoos', 'Piercings', 'Heterochromia', 'Fangs', 'Horns', 'Wings', 'Tail', 'Elf Ears', 'Cat Ears'];
export const ABS_OPTIONS = ['Soft', 'Toned', 'Defined', 'Ripped'];
export const THIGH_OPTIONS = ['Slim', 'Average', 'Thick', 'Thunder'];
export const HIP_OPTIONS = ['Narrow', 'Average', 'Wide', 'Extra Wide'];
export const SHOULDER_OPTIONS = ['Narrow', 'Average', 'Broad', 'V-Shape'];
export const WAIST_OPTIONS = ['Wasp', 'Narrow', 'Average', 'Thick'];
export const CHEST_SIZES = ['Flat', 'Small', 'Medium', 'Large', 'Huge'];
export const BUTT_SIZES = ['Flat', 'Small', 'Medium', 'Large', 'Huge'];
export const EXPERIENCE_OPTIONS = ['Innocent', 'Virgin', 'Curious', 'Experienced', 'Insatiable'];
export const DOMINANCE_OPTIONS = ['Submissive', 'Switch', 'Dominant'];
export const KINK_OPTIONS = ['Praise', 'Degradation', 'Biting/Marking', 'Bondage', 'Exhibitionism', 'Voyeurism', 'Facesitting', 'Smothering', 'Breath Play', 'Breeding', 'Jealousy/Possession'];
export const OUTFIT_VIBES = ['Revealing', 'Lingerie', 'Uniform', 'Leather', 'Barely There'];
export const BACKSTORY_ORIGINS = ['Orphan', 'Noble Birth', 'Self-Made', 'Exile/Outcast', 'Military/Warrior', 'Scholar/Academic', 'Criminal Past', 'Mysterious/Unknown', 'Supernatural Origin', 'Common Folk'];
export const BACKSTORY_TONES = ['Tragic', 'Heroic', 'Comedic', 'Dark/Gritty', 'Wholesome', 'Mysterious', 'Redemptive'];
export const BACKSTORY_ERAS = ['Ancient', 'Medieval', 'Victorian', 'Modern', 'Futuristic', 'Timeless/Fantasy'];
export const RELATIONSHIP_PRESETS = ['Stranger', 'Childhood Friend', 'Rival', 'Best Friend', 'Mentor', 'Student', 'Roommate', 'Co-worker', 'Sparring Partner', 'Sibling', 'Love Interest', 'Secret Admirer', 'Forbidden Romance', 'FWB', 'Ex-lover', 'Arranged Marriage', 'Fake Dating', 'Bodyguard'];

// Guided suggestion chips
export const SUGG_BUILD = ['Petite', 'Slim', 'Athletic', 'Curvy', 'Muscular', 'Plus-size', 'Tall & Lanky'];
export const SUGG_HAIR = ['Short', 'Long', 'Flowing', 'Braided', 'Wild', 'Shaved', 'Pixie'];
export const SUGG_FEATURES = ['Glasses', 'Scars', 'Tattoos', 'Horns', 'Wings', 'Fangs', 'Cat Ears', 'Freckles'];
export const SUGG_RACE = ['Human', 'Elf', 'Demon', 'Vampire', 'Beastkin', 'Android', 'Angel', 'Fae'];
export const SUGG_PERSONALITY = ['Sarcastic', 'Gentle', 'Intense', 'Playful', 'Cold', 'Chaotic', 'Nurturing', 'Mysterious'];
export const SUGG_SPEECH = ['Formal', 'Casual', 'Poetic', 'Blunt', 'Soft-spoken', 'Loud', 'Sarcastic', 'Flirty'];
export const SUGG_ORIGIN = ['Orphan', 'Nobility', 'Self-made', 'Military', 'Criminal past', 'Mysterious origins', 'Small-town', 'Royalty'];
export const SUGG_SETTING = ['Modern', 'Medieval', 'Futuristic', 'Victorian', 'Ancient', 'Post-apocalyptic', 'Urban fantasy'];
export const SUGG_TONE = ['Dark', 'Wholesome', 'Tragic', 'Comedic', 'Mysterious', 'Heroic', 'Bittersweet'];
export const SUGG_REL = ['Strangers', 'Childhood friends', 'Rivals', 'Roommates', 'Love interest', 'Mentor/Student', 'Exes', 'Online friends'];
export const SCENARIO_SEEDS = ['Met at a café', 'Childhood friends', 'Mysterious stranger', 'Coworkers', 'Online match', 'Rescued by them', 'Woke up next to them', 'Battle partners', 'Neighbors', 'Classmates', 'Summoned them'];

// ── Assembly: form → API payload (mirrors creator_state_engine.dart) ──

function outputSettings(f: ChargenForm): Record<string, unknown> {
  return {
    greetingLength: f.greetingLength,
    altGreetingCount: f.altGreetingCount,
    greetingTones: f.greetingTones.length ? f.greetingTones : ['Neutral'],
    generateLorebook: f.generateLorebook,
    loreCategories: f.generateLorebook ? f.loreCategories : [],
    loreDepth: f.loreDepth,
    descriptionDetail: GENERATION_DETAIL[f.generationDetail] ?? '2-3 paragraphs',
  };
}

/** Build the POST /api/chargen/create body for the active mode. */
export function buildPayload(f: ChargenForm): Record<string, unknown> {
  const base = {
    name: f.name.trim(),
    mode: f.mode,
    nsfwEnabled: f.nsfw,
    worldLore: f.worldLore.trim(),
    ...outputSettings(f),
  };

  if (f.mode === 'quick') {
    const concept = f.quickConcept.trim() || 'Create an interesting, unique character for roleplay.';
    const quickConcept = f.nsfw
      ? `${concept}. Adult content enabled: include explicit personality traits and sensual details.`
      : concept;
    return {
      ...base,
      concept: quickConcept,
      personalityKeywords: f.quickKeywords.trim(),
      scenario: f.quickScenario.trim(),
    };
  }

  if (f.mode === 'guided') {
    const parts: string[] = [];
    if (f.vision.trim()) parts.push(f.vision.trim());
    const add = (label: string, v: string) => { if (v.trim()) parts.push(`${label}: ${v.trim()}`); };
    add('Physical build', f.gBuild);
    add('Hair', f.gHair);
    add('Distinguishing features', f.gFeatures);
    add('Race/Species', f.gRace);
    add('Personality', f.gPersonality);
    add('Speech style', f.gSpeech);
    add('Hidden depth', f.gSecret);
    add('Background', f.gOrigin);
    add('Setting', f.gSetting);
    add('Tone', f.gTone);
    add('Relationship to {{user}}', f.gRel);
    add('Opening scenario', f.gRelScenario);
    if (f.nsfw) {
      add('Intimate body details', f.gnBody);
      add('Sexual experience', f.gnExp);
      add('Dominance', f.gnDom);
      add('Turn-ons/kinks', f.gnKinks);
      add('Clothing aesthetic', f.gnClothing);
      add('Sexual personality', f.gnPersonality);
    }
    const ctx: string[] = [];
    const addCtx = (label: string, v: string) => { if (v.trim()) ctx.push(`${label}: ${v.trim()}`); };
    addCtx('Age', f.age);
    addCtx('Sex', f.sex);
    addCtx('Appearance', f.gBuild);
    addCtx('Hair', f.gHair);
    addCtx('Features', f.gFeatures);
    addCtx('Race/Species', f.gRace);
    addCtx('Relationship to {{user}}', f.gRel);
    addCtx('Backstory', f.gOrigin);
    addCtx('Setting', f.gSetting);
    addCtx('Tone', f.gTone);
    if (f.nsfw) {
      const n: string[] = [];
      if (f.gnExp.trim()) n.push(`Experience: ${f.gnExp.trim()}`);
      if (f.gnDom.trim()) n.push(`Dominance: ${f.gnDom.trim()}`);
      if (f.gnKinks.trim()) n.push(`Kinks: ${f.gnKinks.trim()}`);
      if (n.length) ctx.push(n.join(', '));
    }
    const backstory = [
      f.gOrigin.trim(),
      f.gTone.trim() ? `${f.gTone.trim()} tone` : '',
      f.gSetting.trim() ? `${f.gSetting.trim()} setting` : '',
    ].filter(Boolean).join(', ');
    return {
      ...base,
      concept: parts.join('. '),
      personalityKeywords: f.gPersonality.trim(),
      age: f.age.trim(),
      sex: f.sex.trim(),
      relationship: f.gRel.trim(),
      backstory,
      characterContext: ctx.join('\n'),
    };
  }

  // Automated
  const effRace = f.customRace.trim() || f.race;
  const appearance: string[] = [];
  if (effRace) appearance.push(`${effRace} race/species`);
  if (f.bodyType) appearance.push(`${f.bodyType} build`);
  if (f.hairLength) appearance.push(`${f.hairLength} hair`);
  if (f.hairStyle) appearance.push(`${f.hairStyle} hair style`);
  if (f.skinTone) appearance.push(`${f.skinTone} skin`);
  appearance.push(...f.notableFeatures);
  if (f.absCore) appearance.push(`${f.absCore} abs`);
  if (f.thighs) appearance.push(`${f.thighs} thighs`);
  if (f.hips) appearance.push(`${f.hips} hips`);
  if (f.shoulders) appearance.push(`${f.shoulders} shoulders`);
  if (f.waist) appearance.push(`${f.waist} waist`);
  if (f.nsfw) {
    if (f.chestSize) appearance.push(`${f.chestSize} chest`);
    if (f.buttSize) appearance.push(`${f.buttSize} butt`);
  }
  const nsfwParts: string[] = [];
  if (f.nsfw) {
    if (f.experience) nsfwParts.push(`Sexual experience: ${f.experience}`);
    if (f.dominance) nsfwParts.push(`Dominance: ${f.dominance}`);
    if (f.kinks.length) nsfwParts.push(`Kinks: ${f.kinks.join(', ')}`);
    if (f.customKinks.trim()) nsfwParts.push(`Also into: ${f.customKinks.trim()}`);
    if (f.outfitVibe) nsfwParts.push(`Typical outfit vibe: ${f.outfitVibe}`);
  }
  let enriched = f.aConcept.trim();
  if (appearance.length) enriched += `. Physical appearance: ${appearance.join(', ')}`;
  if (nsfwParts.length) enriched += `. ${nsfwParts.join('. ')}`;
  const relationship = [...f.relationships, f.customRelationship.trim()].filter(Boolean).join(', ');
  const backstory = [
    f.backstoryOrigin,
    f.backstoryTone ? `${f.backstoryTone} tone` : '',
    f.backstoryEra ? `${f.backstoryEra} era` : '',
    f.backstoryNotes.trim(),
  ].filter(Boolean).join(', ');
  const ctx = [
    effRace ? `Race/Species: ${effRace}` : '',
    f.age.trim() ? `Age: ${f.age.trim()}` : '',
    f.sex.trim() ? `Sex: ${f.sex.trim()}` : '',
    appearance.length ? `Appearance: ${appearance.join(', ')}` : '',
    relationship ? `Relationship to {{user}}: ${relationship}` : '',
    f.backstoryOrigin ? `Backstory origin: ${f.backstoryOrigin}` : '',
    f.backstoryTone ? `Story tone: ${f.backstoryTone}` : '',
    f.backstoryEra ? `Era/setting: ${f.backstoryEra}` : '',
    f.backstoryNotes.trim() ? `Backstory: ${f.backstoryNotes.trim()}` : '',
    f.nsfw && nsfwParts.length ? nsfwParts.join(', ') : '',
  ].filter(Boolean).join('\n');
  return {
    ...base,
    concept: enriched,
    personalityKeywords: f.aKeywords.trim(),
    age: f.age.trim(),
    sex: f.sex.trim(),
    relationship,
    backstory,
    characterContext: ctx,
  };
}
