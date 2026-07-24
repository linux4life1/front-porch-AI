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

/// Pure prompt data for Expression Packs: which emotions a pack covers and
/// the diffusion-friendly facial-expression phrase appended per emotion.
/// Every label here is a lowercase `EmotionLabels.all` value, stored verbatim
/// as the avatar label so the runtime expression matcher
/// (`a.label?.toLowerCase() == label`) finds it exactly.
library;

/// The 8-emotion starter set (all reachable by both classifiers).
const List<String> kCuratedExpressionSet = [
  'neutral',
  'joy',
  'sadness',
  'anger',
  'fear',
  'surprise',
  'love',
  'embarrassment',
];

/// The full 28-emotion set: EmotionLabels.all minus 'affection' and
/// 'anticipation' (unreachable by the ONNX classifier, which only emits the
/// GoEmotions-28 labels).
const List<String> kFullExpressionSet = [
  'admiration',
  'amusement',
  'anger',
  'annoyance',
  'approval',
  'caring',
  'confusion',
  'curiosity',
  'desire',
  'disappointment',
  'disapproval',
  'disgust',
  'embarrassment',
  'excitement',
  'fear',
  'gratitude',
  'grief',
  'joy',
  'love',
  'nervousness',
  'optimism',
  'pride',
  'realization',
  'relief',
  'remorse',
  'sadness',
  'surprise',
  'neutral',
];

/// Diffusion-friendly facial-expression phrase per emotion
/// (keys == [kFullExpressionSet] exactly). Written as concrete FACIAL
/// GEOMETRY — explicit mouth, brow, and eye states — because CFG-1 /
/// distilled models (Flux, Qwen, turbo SDXL) have no negative prompt: the
/// only way to displace the base portrait's expression is to positively
/// describe the replacement state. Never negate ("no smile" makes text
/// encoders draw MORE smile) and never use teeth-summoning words like
/// "beaming"/"grinning ear to ear" (horror-grin artifacts at high denoise).
const Map<String, String> kExpressionModifiers = {
  'admiration': 'admiring gaze, sparkling wide eyes, raised inner brows, softly parted lips, impressed look',
  'amusement': 'amused lopsided smile, one raised eyebrow, crinkled sparkling eyes, holding back a laugh',
  'anger': 'furious scowl, brows slammed down and drawn together, glaring eyes, clenched jaw, mouth pressed into a hard line',
  'annoyance': 'irritated scowl, narrowed eyes, flat pressed lips, twitching raised eyebrow',
  'approval': 'approving warm closed-lip smile, relaxed brows, steady confident gaze, slight nod',
  'caring': 'tender gentle smile, soft warm eyes, inner eyebrows tilted up in sympathy, head tilted slightly',
  'confusion': 'puzzled frown, one eyebrow raised and one lowered, uneven squinting eyes, mouth slightly open, head tilted',
  'curiosity': 'intrigued bright eyes, both eyebrows lifted, small parted mouth, attentive leaning-in look',
  'desire': 'sultry half-lidded eyes, softly parted lips, flushed cheeks, smoldering longing gaze',
  'disappointment': 'deflated expression, mouth corners turned down, drooping eyelids, lowered sighing gaze',
  'disapproval': 'stern disapproving frown, hard narrowed eyes, tightly pressed lips, chin drawn back',
  'disgust': 'revolted grimace, wrinkled nose, curled upper lip, squinted eyes, head pulled back',
  'embarrassment': 'deep blush across cheeks, averted downcast eyes, awkward sheepish small smile, hunched shoulders',
  'excitement': 'thrilled open smile, wide shining eyes, eyebrows raised high, energized expression',
  'fear': 'terrified expression, wide white-rimmed eyes, brows raised and pulled together, mouth open in a silent gasp, pale face',
  'gratitude': 'moved grateful soft smile, glistening warm eyes, relaxed brows, touched expression',
  'grief': 'devastated anguish, tears streaming down cheeks, inner brows knotted upward, trembling downturned mouth',
  'joy': 'happy warm smile, raised rounded cheeks, sparkling crescent-moon eyes, relaxed brows, radiant glow',
  'love': 'adoring soft gaze, dreamy gentle half-smile, faint blush, tender sparkling eyes',
  'nervousness': 'anxious tight-lipped smile, darting worried eyes, tense raised brows, biting lower lip, bead of sweat',
  'optimism': 'hopeful bright expression, gentle upturned smile, lifted shining gaze, open relaxed face',
  'pride': 'confident smirk, chin lifted high, half-lidded self-assured eyes, satisfied expression',
  'realization': 'sudden dawning look, eyes snapping wide open, eyebrows shooting up, lips parted in a small oh',
  'relief': 'relieved soft exhale, eyes gently closed, easing unburdened smile, relaxed released shoulders',
  'remorse': 'guilty downcast eyes, sorrowful frown, head bowed low, brows pinched together',
  'sadness': 'sad glistening teary eyes, downturned mouth, inner brows raised and pinched, subdued heavy expression',
  'surprise': 'startled expression, eyebrows shot up high, round wide eyes, mouth open in a small o shape',
  'neutral': 'calm neutral expression, relaxed face, level brows, closed relaxed mouth, steady even gaze',
};

/// Per-emotion counter-cues appended to the NEGATIVE prompt (keys ==
/// [kFullExpressionSet]). A free rider: distilled/CFG-1 models ignore
/// negatives entirely (no unconditional branch to steer away from), so this
/// costs them nothing — but classic SD1.5/SDXL at CFG 5–7 get real pressure
/// away from the base portrait's anchored expression (a smiling avatar
/// fights every sad/angry slot) and away from known artifacts (the joy
/// horror-grin: oversized teeth and gums at high denoise).
const Map<String, String> kExpressionNegatives = {
  'admiration': 'frown, scowl, tears',
  'amusement': 'frown, scowl, tears, gaping mouth',
  'anger': 'smile, smiling, grin, laughing',
  'annoyance': 'smile, smiling, grin, laughing',
  'approval': 'frown, scowl, tears',
  'caring': 'frown, scowl, anger',
  'confusion': 'smile, grin, confident gaze',
  'curiosity': 'frown, scowl, bored expression',
  'desire': 'frown, scowl, tears',
  'disappointment': 'smile, grin, laughing',
  'disapproval': 'smile, grin, laughing',
  'disgust': 'smile, grin, serene expression',
  'embarrassment': 'confident gaze, scowl, tears',
  'excitement': 'frown, scowl, tears, bored expression',
  'fear': 'smile, smiling, grin, laughing, calm expression',
  'gratitude': 'frown, scowl, anger',
  'grief': 'smile, smiling, grin, laughing',
  'joy': 'frown, scowl, tears, crying, oversized teeth, gums, gaping mouth',
  'love': 'frown, scowl, disgust',
  'nervousness': 'confident gaze, broad smile, laughing',
  'optimism': 'frown, scowl, tears',
  'pride': 'downcast eyes, frown, timid expression',
  'realization': 'bored expression, closed eyes, frown',
  'relief': 'tension, gritted teeth, frown, wide eyes',
  'remorse': 'smile, grin, confident gaze',
  'sadness': 'smile, smiling, grin, laughing',
  'surprise': 'bored expression, closed mouth, neutral expression',
  'neutral': 'exaggerated expression, wide grin, crying, scowl, open mouth',
};

/// Framing suffix appended once to the base prompt by the pack launcher.
const String kExpressionFraming =
    'close-up portrait, head and shoulders, looking at viewer';

/// The EDIT-path instruction for an emotion — used when an instruction-edit model
/// is loaded (Qwen-Image-Edit / Flux Kontext) instead of the img2img path. It
/// REUSES the field-tested geometry description from [kExpressionModifiers] but
/// frames it as an edit of the base portrait: the model changes only the
/// expression and keeps identity, so no character/framing prompt is needed (the
/// reference image supplies both). Deriving from the one table (rather than a
/// hand-written second one) means the img2img and edit paths can never drift.
String expressionEditInstruction(String emotion) {
  final desc = kExpressionModifiers[emotion] ?? emotion;
  return 'Change only the facial expression to: $desc. '
      'Keep the same person, hairstyle, outfit, pose, camera framing, and '
      'background exactly as they are.';
}
