// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Current preserves existing pack wording until a level is chosen.
enum ExpressionIntensity {
  current('Default (original)'),
  subtle('Subtle'),
  clear('Clear'),
  strong('Strong');

  const ExpressionIntensity(this.label);
  final String label;
  static ExpressionIntensity parse(Object? value) {
    for (final level in values) {
      if (value == level.name) return level;
    }
    throw const FormatException(
      'Choose current, subtle, clear, or strong expression intensity.',
    );
  }
}

String? expressionIntensityDescription(
  String emotion,
  ExpressionIntensity level,
) {
  if (level == ExpressionIntensity.current) return null;
  final row = _descriptions[emotion];
  return row == null ? null : row[level.index - 1];
}

const _descriptions = <String, List<String>>{
  'admiration': [
    'slightly lifted inner brows, attentive eyes, softly parted lips',
    'lifted inner brows, bright attentive eyes, softly parted lips',
    'high raised brows, wide bright eyes, parted lips in wonder',
  ],
  'amusement': [
    'faint asymmetric closed-mouth smile, gently crinkled eyes',
    'asymmetric smile, one raised brow, crinkled eyes',
    'broad asymmetric closed-mouth smile, strongly crinkled eyes, raised brow',
  ],
  'anger': [
    'slightly drawn-together brows, gently tightened lips, naturally open eyes',
    'brows drawn down and together, moderately narrowed eyes, pressed lips',
    'deeply furrowed brows, sharply narrowed eyes, tense jaw, firmly compressed lips',
  ],
  'annoyance': [
    'slightly narrowed eyes, a small brow crease, lightly pressed lips',
    'narrowed eyes, one lowered brow, pressed lips',
    'deep brow crease, sharply narrowed eyes, tightly pressed lips',
  ],
  'approval': [
    'small closed-lip smile, relaxed brows, steady gaze',
    'warm closed-lip smile, relaxed brows, steady gaze',
    'broad closed-lip smile, raised cheeks, bright steady gaze',
  ],
  'caring': [
    'faint gentle smile, softened eyes, slightly lifted inner brows',
    'gentle smile, soft eyes, lifted inner brows',
    'warm broad closed-mouth smile, deeply softened eyes, clearly lifted inner brows',
  ],
  'confusion': [
    'one brow slightly raised, small brow crease, lightly parted lips',
    'one raised brow, opposite lowered brow, parted lips',
    'strongly uneven brows, squinting eyes, visibly parted lips',
  ],
  'curiosity': [
    'slightly raised brows, attentive eyes, relaxed lips',
    'raised brows, bright attentive eyes, lightly parted lips',
    'high raised brows, wide attentive eyes, visibly parted lips',
  ],
  'desire': [
    'slightly lowered eyelids, faint smile, softly relaxed lips',
    'half-lidded eyes, softly parted lips, faint cheek blush',
    'strongly lowered eyelids, parted lips, pronounced cheek blush',
  ],
  'disappointment': [
    'slightly lowered mouth corners, softened eyelids',
    'downturned mouth corners, drooping eyelids, lowered gaze',
    'deeply downturned mouth, heavy drooping eyelids, visibly tense inner brows',
  ],
  'disapproval': [
    'small brow crease, lightly pressed lips, steady eyes',
    'furrowed brows, narrowed eyes, firmly pressed lips',
    'deeply furrowed brows, sharply narrowed eyes, tightly pressed lips',
  ],
  'disgust': [
    'slight nose wrinkle, small upper-lip lift',
    'wrinkled nose, raised upper lip, narrowed eyes',
    'deep nose wrinkles, strongly curled upper lip, tightly narrowed eyes',
  ],
  'embarrassment': [
    'faint cheek blush, small hesitant smile, lowered gaze',
    'cheek blush, uneven small smile, averted eyes',
    'pronounced cheek blush, tightly hesitant smile, strongly averted eyes',
  ],
  'excitement': [
    'small smile, slightly raised brows, bright eyes',
    'open smile, raised brows, bright wide eyes',
    'broad open smile, high raised brows, wide shining eyes',
  ],
  'fear': [
    'slightly raised inner brows, tense lips, alert eyes',
    'raised and drawn-together brows, widened eyes, parted lips',
    'high tense brows, very wide eyes, open mouth in a gasp',
  ],
  'gratitude': [
    'small warm smile, softened eyes',
    'warm smile, softened bright eyes, gently raised cheeks',
    'broad warm smile, glistening eyes, strongly raised cheeks',
  ],
  'grief': [
    'gently raised inner brows, downturned lips, lowered gaze',
    'knotted inner brows, downturned mouth, glistening eyes',
    'deeply knotted inner brows, trembling downturned mouth, visible tears',
  ],
  'joy': [
    'small closed-lip smile, gently lifted cheeks, naturally open eyes',
    'warm smile, raised cheeks, gently crinkled eyes',
    'broad closed-mouth smile, strongly raised cheeks, deeply crinkled eyes',
  ],
  'love': [
    'faint gentle smile, softened gaze',
    'gentle smile, soft half-lidded eyes, faint blush',
    'warm broad closed-mouth smile, deeply softened eyes, visible blush',
  ],
  'nervousness': [
    'slightly tense brows, lightly pressed lips, alert eyes',
    'tense raised brows, tight hesitant smile, worried eyes',
    'high tense brows, tightly drawn lips, wide worried eyes',
  ],
  'optimism': [
    'small upturned smile, bright steady eyes',
    'upturned smile, lifted brows, bright eyes',
    'broad upturned smile, high relaxed brows, shining eyes',
  ],
  'pride': [
    'small asymmetric smile, steady eyes',
    'confident asymmetric smile, slightly lowered eyelids',
    'pronounced asymmetric smile, strongly lowered eyelids, raised cheek',
  ],
  'realization': [
    'slightly raised brows, attentive eyes, lightly parted lips',
    'raised brows, widened eyes, small rounded mouth',
    'high raised brows, very wide eyes, clearly rounded open mouth',
  ],
  'relief': [
    'slightly relaxed brows and lips, softened eyes',
    'relaxed brows, soft smile, gently lowered eyelids',
    'deeply relaxed brows, clear smile, softly closed eyes',
  ],
  'remorse': [
    'slightly raised inner brows, lowered gaze, downturned lips',
    'pinched inner brows, downturned mouth, lowered gaze',
    'deeply pinched inner brows, trembling downturned mouth, strongly lowered gaze',
  ],
  'sadness': [
    'slightly raised inner brows, gently downturned mouth, softened eyes',
    'raised pinched inner brows, downturned mouth, heavy eyelids',
    'strongly pinched inner brows, deeply downturned mouth, tearful eyes',
  ],
  'surprise': [
    'slightly raised brows, wider eyes, lightly parted lips',
    'raised brows, wide eyes, small rounded mouth',
    'high raised brows, very wide eyes, clearly open rounded mouth',
  ],
  'neutral': [
    'relaxed brows, naturally open eyes, closed relaxed mouth',
    'relaxed brows, naturally open eyes, closed relaxed mouth',
    'relaxed brows, naturally open eyes, closed relaxed mouth',
  ],
};
