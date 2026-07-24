/** 27 emotion -> 6 DSP parameter profiles.
 *  Each tuple: [pitchShiftSemitones, pitchVarianceScale,
 *               brightnessDb, tension, breathiness, speedRatio]
 *  Mirrors lib/services/emotional_voice_dsp.dart exactly. */
export const EMOTION_PROFILES: Record<string, readonly number[]> = {
  admiration:      [ 1.5,  1.3,  2.0, 0.2, 0.10, 1.00],
  amusement:       [ 3.0,  1.6,  3.0, 0.0, 0.00, 1.08],
  anger:           [ 2.0,  1.8,  6.0, 0.5, 0.00, 1.10],
  annoyance:       [ 1.0,  1.3,  3.0, 0.3, 0.00, 1.05],
  approval:        [ 0.5,  1.1,  1.5, 0.1, 0.00, 1.00],
  caring:          [-1.0,  0.8, -1.0, 0.1, 0.20, 0.95],
  confusion:       [ 0.0,  1.2,  0.0, 0.1, 0.08, 0.98],
  curiosity:       [ 2.0,  1.4,  1.0, 0.0, 0.00, 1.03],
  desire:          [-1.5,  0.7, -2.0, 0.2, 0.30, 0.90],
  disappointment:  [-2.0,  0.6, -3.0, 0.1, 0.20, 0.92],
  disgust:         [-0.5,  0.9,  0.0, 0.3, 0.05, 0.95],
  embarrassment:   [-2.0,  0.7, -1.0, 0.0, 0.20, 0.93],
  excitement:      [ 4.0,  1.8,  5.0, 0.0, 0.00, 1.12],
  fear:            [ 3.0,  1.5,  1.0, 0.2, 0.20, 1.06],
  gratitude:       [ 1.0,  1.1,  1.0, 0.1, 0.10, 0.98],
  grief:           [-4.0,  0.4, -4.0, 0.0, 0.30, 0.85],
  joy:             [ 3.0,  1.6,  4.0, 0.0, 0.00, 1.08],
  love:            [-1.5,  0.6, -1.0, 0.2, 0.30, 0.88],
  nervousness:     [ 2.0,  1.3,  0.0, 0.2, 0.15, 1.04],
  optimism:        [ 1.5,  1.3,  2.0, 0.0, 0.00, 1.03],
  pride:           [ 2.0,  1.4,  3.0, 0.1, 0.00, 1.03],
  realization:     [ 2.5,  1.5,  1.0, 0.0, 0.00, 1.00],
  relief:          [-0.5,  0.9,  0.0, 0.0, 0.15, 0.97],
  remorse:         [-3.0,  0.5, -2.0, 0.1, 0.25, 0.88],
  sadness:         [-4.0,  0.4, -5.0, 0.0, 0.35, 0.82],
  surprise:        [ 5.0,  1.8,  5.0, 0.2, 0.00, 1.08],
  neutral:         [ 0.0,  1.0,  0.0, 0.0, 0.00, 1.00],
};

export const NEUTRAL_PROFILE = EMOTION_PROFILES.neutral;
