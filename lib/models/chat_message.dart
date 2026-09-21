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

import 'package:front_porch_ai/utils/reasoning_markers.dart';

/// Metadata flag for backend-down / generation-error System banners.
/// Status, not story: omit from the prompt and from the saved transcript.
const String kStatusBannerMeta = 'is_status_banner';

enum GenerationMode { normal, continue_, impersonate }

/// Tracks the distinct phases of text generation for UI display.
/// Each phase maps to a user-visible status message.
enum GenerationPhase {
  /// Not generating.
  idle,

  /// Building the prompt context (lorebook, memories, history, etc.).
  preparing,

  /// HTTP request sent, waiting for response + prompt processing.
  /// For KoboldCPP this is the prefill/eval phase which can be long.
  prefilling,

  /// Tokens arriving but inside &lt;think&gt;...&lt;/think&gt; tags (reasoning model).
  thinking,

  /// Display buffer is accumulating tokens before smooth playback begins.
  buffering,

  /// Tokens are actively being generated and displayed to the user.
  generating,
}

class ChatMessage {
  final List<String> swipes;
  int swipeIndex;
  final String sender;
  final bool isUser;
  final String?
  characterId; // which character card sent this (null = user or 1:1 mode)
  final List<int> swipeDurations; // thinking duration in ms per swipe

  String get text =>
      (swipes.isNotEmpty && swipeIndex >= 0 && swipeIndex < swipes.length)
      ? swipes[swipeIndex]
      : '';
  set text(String value) {
    if (swipes.isNotEmpty && swipeIndex >= 0 && swipeIndex < swipes.length) {
      swipes[swipeIndex] = value;
    }
  }

  /// Returns text with &lt;think&gt;...&lt;/think&gt; blocks removed for display.
  /// Also handles in-progress thinking (no closing tag yet during streaming).
  // ── Parse caches ──
  // displayText / thinkingContent run regexes over the FULL message text and
  // are read several times per bubble per rebuild — and during streaming the
  // whole visible list rebuilds many times a second, so uncached getters
  // meant thousands of full-text regex scans/sec for messages that never
  // changed. Cache keyed on the source string: identical() is O(1) for the
  // unchanged majority (their string object never changes); only the actively
  // streaming message (whose text is reassigned per flush) recomputes.
  static final RegExp _closedThinkRe = RegExp(
    r'<think>[\s\S]*?</think>\s*',
    caseSensitive: false,
  );
  static final RegExp _openThinkRe = RegExp(
    r'<think>[\s\S]*$',
    caseSensitive: false,
  );
  static final RegExp _closedThinkCaptureRe = RegExp(
    r'<think>([\s\S]*?)</think>',
    caseSensitive: false,
  );
  static final RegExp _openThinkCaptureRe = RegExp(
    r'<think>([\s\S]*?)$',
    caseSensitive: false,
  );
  // Fast-path probe: MUST be case-insensitive like the strip regexes above
  // (<THINK> is valid — there's a dedicated test for it).
  static final RegExp _hasThinkRe = RegExp(r'<think>', caseSensitive: false);
  String? _displayTextSource;
  String? _displayTextCache;
  String? _thinkingSource;
  String? _thinkingCache;

  String get displayText {
    final raw = text;
    if (identical(raw, _displayTextSource)) return _displayTextCache!;
    final source = reasoningMarkersMayBePresent(raw)
        ? canonicalizeReasoning(raw)
        : raw;
    final result = !_hasThinkRe.hasMatch(source)
        ? source.trim()
        : source
              .replaceAll(_closedThinkRe, '')
              .replaceAll(_openThinkRe, '')
              .trim();
    _displayTextSource = raw;
    _displayTextCache = result;
    return result;
  }

  /// Text to feed LLM prompt/eval CONTEXT for this message: the visible text,
  /// but annotated when the message carries a user-attached photo so realism
  /// evals, the guest-director gate, and any other history consumer never see
  /// a blank user turn (which would score bond/trust against an apparently
  /// silent user). Uses the stored caption once the captioner has written it.
  /// Non-photo messages return [displayText] unchanged.
  String get promptText {
    final md = activeMetadata;
    if (md?['is_user_image'] == true) {
      final caption = (md?['image_caption'] as String? ?? '').trim();
      final marker = caption.isEmpty
          ? '[shared a photo]'
          : '[shared a photo: $caption]';
      final visible = displayText.trim();
      return visible.isEmpty ? marker : '$visible $marker';
    }
    return displayText;
  }

  /// Backend-down / generation-error banners. Not story.
  bool get isStatusBanner => activeMetadata?[kStatusBannerMeta] == true;

  /// One `sender: text` line for the chat-history section of a generation
  /// prompt. Always think-stripped ([promptText]): feeding raw [text] re-injects
  /// every prior `<think>` plan into the next turn, so a thinking model on a
  /// long chat re-executes the previous scene on every regenerate (Nina
  /// session 1786256661829, 2026-08-11 — ~39% of history tokens were think
  /// blocks; 8 of 10 rerolls opened with the prior massage beat).
  String toPromptHistoryLine() {
    if (isStatusBanner) return '';
    if (characterId == '__director__') {
      return '[Director: $text]';
    }
    if (activeMetadata?['is_generated_image'] == true && displayText.isEmpty) {
      final prompt = (activeMetadata?['image_prompt'] as String? ?? '').trim();
      final short = prompt.length > 120
          ? '${prompt.substring(0, 120)}…'
          : prompt;
      return '$sender: [shares a generated image'
          '${short.isEmpty ? '' : ': $short'}]';
    }
    return '$sender: $promptText';
  }

  /// Returns the thinking content (between &lt;think&gt; tags), or null if none.
  /// Handles both completed and in-progress (streaming) think blocks.
  String? get thinkingContent {
    final raw = text;
    if (identical(raw, _thinkingSource)) return _thinkingCache;
    final source = reasoningMarkersMayBePresent(raw)
        ? canonicalizeReasoning(raw)
        : raw;
    String? result;
    if (_hasThinkRe.hasMatch(source)) {
      final closed = _closedThinkCaptureRe.firstMatch(source);
      result = closed != null
          ? closed.group(1)?.trim()
          : _openThinkCaptureRe.firstMatch(source)?.group(1)?.trim();
    }
    _thinkingSource = raw;
    _thinkingCache = result;
    return result;
  }

  /// Whether this message has thinking content (either from tags or tracked duration)
  bool get hasThinking => thinkingContent != null || thinkingDurationMs > 0;

  int get thinkingDurationMs =>
      (swipeIndex >= 0 && swipeIndex < swipeDurations.length)
      ? swipeDurations[swipeIndex]
      : 0;
  set thinkingDurationMs(int value) {
    if (swipeIndex < 0) return;
    while (swipeDurations.length <= swipeIndex) {
      swipeDurations.add(0);
    }
    swipeDurations[swipeIndex] = value;
  }

  int? thinkingStartTime; // Runtime only, for live timer
  Map<String, dynamic>? metadata; // Legacy single metadata
  List<Map<String, dynamic>?> swipeMetadata; // Per-swipe metadata

  Map<String, dynamic>? get activeMetadata {
    if (swipeIndex >= 0 && swipeIndex < swipeMetadata.length) {
      return swipeMetadata[swipeIndex] ?? metadata;
    }
    return metadata;
  }

  set activeMetadata(Map<String, dynamic>? value) {
    if (swipeIndex < 0) return;
    while (swipeMetadata.length <= swipeIndex) {
      swipeMetadata.add(null);
    }
    swipeMetadata[swipeIndex] = value;
  }

  ChatMessage({
    required String text,
    required this.sender,
    required this.isUser,
    this.characterId,
    List<String>? swipes,
    int? swipeIndex,
    List<int>? swipeDurations,
    this.metadata,
    List<Map<String, dynamic>?>? swipeMetadata,
  }) : swipes = swipes ?? [text],
       swipeIndex = swipeIndex ?? 0,
       swipeDurations = swipeDurations ?? [0],
       swipeMetadata = swipeMetadata ?? [metadata] {
    // Always clamp swipeIndex to a valid range for the swipes list.
    // This prevents RangeError crashes from corrupted DB rows or previous buggy state.
    final int listLen = this.swipes.length;
    if (this.swipeIndex < 0 || this.swipeIndex >= listLen) {
      this.swipeIndex = 0;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'sender': sender,
      'is_user': isUser,
      if (characterId != null) 'character_id': characterId,
      'swipes': swipes,
      'swipe_index': swipeIndex,
      'swipe_durations': swipeDurations,
      if (metadata != null) 'metadata': metadata,
      if (swipeMetadata.any((e) => e != null)) 'swipe_metadata': swipeMetadata,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final List<String>? savedSwipes = (json['swipes'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();
    final List<int>? savedDurations =
        (json['swipe_durations'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toList();
    final String fallbackText = json['text'] ?? '';
    final List<Map<String, dynamic>?>? savedSwipeMetadata =
        (json['swipe_metadata'] as List<dynamic>?)
            ?.map((e) => e != null ? Map<String, dynamic>.from(e as Map) : null)
            .toList();

    return ChatMessage(
      text: fallbackText,
      sender: json['sender'] ?? '',
      isUser: json['is_user'] ?? false,
      characterId: json['character_id'],
      swipes: savedSwipes ?? [fallbackText],
      swipeIndex: json['swipe_index'] ?? 0,
      swipeDurations: savedDurations ?? [0],
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
      swipeMetadata: savedSwipeMetadata,
    );
  }
}
