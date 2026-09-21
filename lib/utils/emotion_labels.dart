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

import 'package:flutter/material.dart';

part 'emotion_labels.nuanced.dart';

/// Standard emotion labels for character expression images.
///
/// Based on the 28-class go-emotions ONNX model
/// (Cohee/distilbert-base-uncased-go-emotions-onnx) with two additions:
/// 'affection' and 'anticipation' for richer expression variety.
class EmotionLabels {
  /// All 28 standard go-emotions labels plus 2 additions.
  static const List<String> all = [
    'admiration',
    'affection',
    'amusement',
    'anger',
    'annoyance',
    'anticipation',
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

  /// Emoji representation for each standard emotion label.
  static const Map<String, String> emoji = {
    'admiration': '🤩',
    'affection': '💕',
    'amusement': '😄',
    'anger': '😠',
    'annoyance': '😤',
    'anticipation': '👀',
    'approval': '👍',
    'caring': '🤗',
    'confusion': '😕',
    'curiosity': '🧐',
    'desire': '🥵',
    'disappointment': '😞',
    'disapproval': '👎',
    'disgust': '🤢',
    'embarrassment': '😳',
    'excitement': '🤩',
    'fear': '😨',
    'gratitude': '🙏',
    'grief': '😭',
    'joy': '😁',
    'love': '😍',
    'nervousness': '😰',
    'optimism': '😊',
    'pride': '😎',
    'realization': '💡',
    'relief': '😌',
    'remorse': '😔',
    'sadness': '😢',
    'surprise': '😲',
    'neutral': '😐',
  };

  /// Maps nuanced LLM-generated emotion words to standard expression labels.
  ///
  /// The Realism Engine LLM produces nuanced words like "elated", "wistful",
  /// "starstruck", etc. This mapping translates them to one of the standard
  /// labels so the correct expression sprite can be shown.
  ///
  /// If an emotion word is not found in this map, the caller should trigger
  /// an LLM re-classification to pick from [all] labels.
  static const Map<String, String> nuancedToStandard = _nuancedToStandard;

  /// Prompt template for LLM re-classification when the emotion is unmapped.
  ///
  /// Use this to ask the LLM to classify an unknown emotion word into one of
  /// the standard labels. Send this as a quick single-call prompt and parse
  /// the response for a word from [all].
  static String buildReclassifyPrompt(String unknownEmotion) {
    final labels = all.join(', ');
    return 'Classify the emotion "$unknownEmotion" into exactly ONE of these labels: '
        '$labels.\n'
        'Respond with ONLY the label name, nothing else.';
  }

  /// Returns a suitable accent color for a thin ring around a character's avatar
  /// based on their current emotion label. Used for visual state in group UIs
  /// (app bar stacked avatars, member cards, etc.).
  static Color ringColor(String? emotion) {
    if (emotion == null) return Colors.grey;
    switch (emotion.toLowerCase()) {
      case 'joy':
      case 'amusement':
      case 'excitement':
        return Colors.amber;
      case 'sadness':
      case 'grief':
      case 'disappointment':
        return Colors.blueGrey;
      case 'anger':
      case 'annoyance':
        return Colors.redAccent;
      case 'fear':
      case 'nervousness':
        return Colors.deepPurpleAccent;
      case 'affection':
      case 'love':
        return Colors.pinkAccent;
      case 'anticipation':
      case 'desire':
        return Colors.orangeAccent;
      default:
        return Colors.grey;
    }
  }
}
