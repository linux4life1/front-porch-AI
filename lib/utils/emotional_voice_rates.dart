// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Per-emotion rate factors for Emotional Voice.
///
/// Applied as WAV resampling (the "tape speed" trick): rate > 1.0 speeds up
/// audio (higher pitch, shorter duration), rate < 1.0 slows it down (lower
/// pitch, longer duration).  All values stay within ±2 semitones so the voice
/// reads as mood, not as a different person.
///
/// ## Semitone formula
///   rate = 2^(semitones / 12)
/// Reference: mixxxdj.github.io/pitch-percentages/
///
///   Joy / Excitement  (+1 semitone) → 2^(1/12)  ≈ 1.059  (uses 1.06)
///   Sadness / Remorse (-1 semitone) → 2^(-1/12) ≈ 0.944  (uses 0.94)
///   Grief             (-2 semitones) → 2^(-2/12) ≈ 0.891  (uses 0.90)
///
/// ## Academic grounding
/// The directional mapping (high-arousal emotions → faster/higher pitch,
/// low-arousal → slower/lower pitch) is supported by:
///   - Banse & Scherer (1996) — acoustic profiles for 14 emotions
///   - Murray & Arnott (1993) — survey confirming joy/surprise → faster,
///     sadness/grief → slower
class EmotionalVoiceRates {
  static const Map<String, double> _rates = {
    'admiration': 1.02,
    'affection': 1.02,
    'amusement': 1.04,
    'anger': 0.95,
    'annoyance': 0.97,
    'anticipation': 1.03,
    'approval': 1.02,
    'caring': 1.01,
    'confusion': 1.0,
    'curiosity': 1.02,
    'desire': 0.98,
    'disappointment': 0.95,
    'disapproval': 0.96,
    'disgust': 0.95,
    'embarrassment': 0.97,
    'excitement': 1.06,
    'fear': 1.04,
    'gratitude': 1.02,
    'grief': 0.90,
    'joy': 1.06,
    'love': 1.02,
    'nervousness': 1.03,
    'optimism': 1.04,
    'pride': 1.02,
    'realization': 1.01,
    'relief': 1.01,
    'remorse': 0.94,
    'sadness': 0.94,
    'surprise': 1.05,
    'neutral': 1.0,
  };

  static const Map<String, double> _elevenlabsStyle = {
    'admiration': 0.3,
    'affection': 0.4,
    'amusement': 0.5,
    'anger': 0.7,
    'annoyance': 0.5,
    'anticipation': 0.4,
    'approval': 0.2,
    'caring': 0.3,
    'confusion': 0.2,
    'curiosity': 0.3,
    'desire': 0.5,
    'disappointment': 0.3,
    'disapproval': 0.4,
    'disgust': 0.6,
    'embarrassment': 0.3,
    'excitement': 0.6,
    'fear': 0.5,
    'gratitude': 0.2,
    'grief': 0.4,
    'joy': 0.5,
    'love': 0.4,
    'nervousness': 0.3,
    'optimism': 0.4,
    'pride': 0.3,
    'realization': 0.2,
    'relief': 0.2,
    'remorse': 0.3,
    'sadness': 0.3,
    'surprise': 0.5,
    'neutral': 0.0,
  };

  /// Returns the resample rate factor for [emotion], or 1.0 if unknown.
  static double rateFor(String? emotion) {
    if (emotion == null) return 1.0;
    return _rates[emotion.toLowerCase()] ?? 1.0;
  }

  /// Returns an ElevenLabs style value (0.0-1.0) for [emotion].
  static double elevenlabsStyleFor(String? emotion) {
    if (emotion == null) return 0.0;
    return _elevenlabsStyle[emotion.toLowerCase()] ?? 0.0;
  }
}
