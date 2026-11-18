// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for the extracted ChatMessage model (and supporting enums).
// Placed under test/models/ per Stage 1 refactoring requirements.
// These tests cover construction, swipe handling, computed getters (displayText,
// thinkingContent, hasThinking, activeMetadata), duration tracking, and
// JSON serialization roundtrips. They are designed to catch regressions
// in the pure data model after extraction from chat_service.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/chat_message.dart';

void main() {
  group('ChatMessage construction and swipes', () {
    test(
      'defaults swipes, swipeIndex, swipeDurations, swipeMetadata from text',
      () {
        final msg = ChatMessage(text: 'Hello', sender: 'Luna', isUser: false);
        expect(msg.swipes, ['Hello']);
        expect(msg.swipeIndex, 0);
        expect(msg.swipeDurations, [0]);
        expect(msg.swipeMetadata, [null]);
        expect(msg.text, 'Hello');
        expect(msg.sender, 'Luna');
        expect(msg.isUser, false);
        expect(msg.characterId, isNull);
      },
    );

    test('accepts explicit swipes, index, durations, metadata', () {
      final msg = ChatMessage(
        text: 'ignored',
        sender: 'User',
        isUser: true,
        swipes: ['A', 'B', 'C'],
        swipeIndex: 2,
        swipeDurations: [10, 20, 30],
        metadata: {'k': 'v'},
        swipeMetadata: [
          null,
          null,
          {'x': 1},
        ],
      );
      expect(msg.swipes, ['A', 'B', 'C']);
      expect(msg.swipeIndex, 2);
      expect(msg.text, 'C');
      expect(msg.swipeDurations, [10, 20, 30]);
      expect(msg.activeMetadata, {'x': 1});
    });

    test('clamps invalid swipeIndex to 0 on construction', () {
      final msgNeg = ChatMessage(
        text: 'x',
        sender: 'S',
        isUser: false,
        swipes: ['one', 'two'],
        swipeIndex: -5,
      );
      expect(msgNeg.swipeIndex, 0);

      final msgTooBig = ChatMessage(
        text: 'x',
        sender: 'S',
        isUser: false,
        swipes: ['one'],
        swipeIndex: 99,
      );
      expect(msgTooBig.swipeIndex, 0);
    });

    test('characterId is stored when provided (group chat scenario)', () {
      final msg = ChatMessage(
        text: 'Hi',
        sender: 'Alice',
        isUser: false,
        characterId: 'char-uuid-123',
      );
      expect(msg.characterId, 'char-uuid-123');
    });
  });

  group('ChatMessage text and swipes', () {
    test('text getter/setter targets current swipe', () {
      final msg = ChatMessage(
        text: 'orig',
        sender: 'L',
        isUser: false,
        swipes: ['s0', 's1'],
        swipeIndex: 1,
      );
      expect(msg.text, 's1');
      msg.text = 'updated';
      expect(msg.swipes[1], 'updated');
      expect(msg.text, 'updated');
    });
  });

  group('ChatMessage displayText and thinkingContent', () {
    test('displayText strips completed <think> blocks', () {
      final msg = ChatMessage(
        text: 'Hello <think>secret</think> world',
        sender: 'L',
        isUser: false,
      );
      expect(msg.displayText, 'Hello world');
    });

    test('displayText strips in-progress think blocks (streaming)', () {
      final msg = ChatMessage(
        text: 'Visible <think>partial thought',
        sender: 'L',
        isUser: false,
      );
      expect(msg.displayText, 'Visible');
    });

    test('thinkingContent extracts from completed block', () {
      final msg = ChatMessage(
        text: 'Hi <think>deep thoughts here</think> there',
        sender: 'L',
        isUser: false,
      );
      expect(msg.thinkingContent, 'deep thoughts here');
    });

    test('thinkingContent extracts from in-progress block', () {
      final msg = ChatMessage(
        text: 'Start <think>still thinking',
        sender: 'L',
        isUser: false,
      );
      expect(msg.thinkingContent, 'still thinking');
    });

    test(
      'hasThinking is true when thinkingContent present or duration > 0',
      () {
        final withTag = ChatMessage(
          text: 'x <think>y</think>',
          sender: 'L',
          isUser: false,
        );
        expect(withTag.hasThinking, true);

        final withDuration = ChatMessage(text: 'x', sender: 'L', isUser: false);
        withDuration.thinkingDurationMs = 123;
        expect(withDuration.hasThinking, true);

        final neither = ChatMessage(text: 'plain', sender: 'L', isUser: false);
        expect(neither.hasThinking, false);
      },
    );
  });

  group('ChatMessage thinkingDurationMs', () {
    test('getter/setter grows list as needed and targets swipeIndex', () {
      final msg = ChatMessage(
        text: 'a',
        sender: 'L',
        isUser: false,
        swipes: ['a', 'b'],
        swipeIndex: 1,
      );
      expect(msg.thinkingDurationMs, 0);
      msg.thinkingDurationMs = 450;
      expect(msg.thinkingDurationMs, 450);
      expect(msg.swipeDurations, [0, 450]);

      // switch swipe
      msg.swipeIndex = 0;
      expect(msg.thinkingDurationMs, 0);
      msg.thinkingDurationMs = 99;
      expect(msg.swipeDurations, [99, 450]);
    });

    test('setter is no-op if swipeIndex < 0', () {
      final msg = ChatMessage(text: 'x', sender: 'L', isUser: false);
      msg.swipeIndex = -1;
      msg.thinkingDurationMs = 500; // should not crash or grow
      expect(msg.swipeDurations, [0]);
    });
  });

  group('ChatMessage metadata and activeMetadata', () {
    test('activeMetadata falls back to legacy metadata when no per-swipe', () {
      final msg = ChatMessage(
        text: 'm',
        sender: 'L',
        isUser: false,
        metadata: {'legacy': true},
      );
      expect(msg.activeMetadata, {'legacy': true});
    });

    test('activeMetadata prefers per-swipe over legacy', () {
      final msg = ChatMessage(
        text: 'm',
        sender: 'L',
        isUser: false,
        metadata: {'legacy': 1},
        swipes: ['m0', 'm1'],
        swipeMetadata: [
          null,
          {'per': 2},
        ],
        swipeIndex: 1,
      );
      expect(msg.activeMetadata, {'per': 2});
    });

    test('writing metadata does not reach a live swipe slot', () {
      // Clock rewind stamps must mutate activeMetadata. Assigning
      // metadata after realism has already parked a swipe map is
      // invisible to regen/delete, which read activeMetadata.
      final msg = ChatMessage(
        text: 'm',
        sender: 'L',
        isUser: false,
        metadata: {'legacy': 1},
        swipeMetadata: [
          {'realism_state': <String, dynamic>{}},
        ],
      );
      msg.metadata = {'story_clock_before': 'lost'};
      expect(msg.activeMetadata!.containsKey('story_clock_before'), isFalse);
      msg.activeMetadata!['story_clock_before'] = 'kept';
      expect(msg.activeMetadata!['story_clock_before'], 'kept');
    });

    test('activeMetadata setter grows swipeMetadata list', () {
      final msg = ChatMessage(
        text: 'm',
        sender: 'L',
        isUser: false,
        swipeIndex: 0,
      );
      msg.activeMetadata = {'set': 'value'};
      expect(msg.swipeMetadata[0], {'set': 'value'});
      expect(msg.activeMetadata, {'set': 'value'});
    });
  });

  group('ChatMessage JSON serialization', () {
    test('toJson includes core fields and omits nulls appropriately', () {
      final msg = ChatMessage(
        text: 'hello',
        sender: 'User',
        isUser: true,
        characterId: null,
      );
      final json = msg.toJson();
      expect(json['text'], 'hello');
      expect(json['sender'], 'User');
      expect(json['is_user'], true);
      expect(json.containsKey('character_id'), false);
      expect(json['swipes'], ['hello']);
      expect(json['swipe_index'], 0);
      expect(json.containsKey('metadata'), false);
      expect(json.containsKey('swipe_metadata'), false);
    });

    test('toJson includes character_id and metadata when present', () {
      final msg = ChatMessage(
        text: 'hi',
        sender: 'A',
        isUser: false,
        characterId: 'cid-42',
        metadata: {'m': 1},
      );
      final json = msg.toJson();
      expect(json['character_id'], 'cid-42');
      expect(json['metadata'], {'m': 1});
    });

    test('toJson includes swipe_metadata only when at least one non-null', () {
      final msgWith = ChatMessage(
        text: 'x',
        sender: 'L',
        isUser: false,
        swipeMetadata: [
          null,
          {'a': 1},
        ],
        swipeIndex: 1,
      );
      expect(msgWith.toJson().containsKey('swipe_metadata'), true);

      final msgWithout = ChatMessage(
        text: 'x',
        sender: 'L',
        isUser: false,
        swipeMetadata: [null, null],
      );
      expect(msgWithout.toJson().containsKey('swipe_metadata'), false);
    });

    test('fromJson roundtrips basic message', () {
      final original = ChatMessage(text: 'round', sender: 'S', isUser: true);
      final restored = ChatMessage.fromJson(original.toJson());
      expect(restored.text, 'round');
      expect(restored.sender, 'S');
      expect(restored.isUser, true);
      expect(restored.swipes, ['round']);
    });

    test(
      'fromJson roundtrips swipes, index, durations, characterId, metadata',
      () {
        final original = ChatMessage(
          text: 's0',
          sender: 'Char',
          isUser: false,
          characterId: 'c-uuid',
          swipes: ['s0', 's1'],
          swipeIndex: 1,
          swipeDurations: [5, 15],
          metadata: {'foo': 'bar'},
          swipeMetadata: [
            null,
            {'sw': true},
          ],
        );
        final restored = ChatMessage.fromJson(original.toJson());
        expect(restored.swipes, ['s0', 's1']);
        expect(restored.swipeIndex, 1);
        expect(restored.text, 's1');
        expect(restored.swipeDurations, [5, 15]);
        expect(restored.characterId, 'c-uuid');
        expect(restored.metadata, {'foo': 'bar'});
        expect(restored.swipeMetadata[1], {'sw': true});
        expect(restored.activeMetadata, {'sw': true});
      },
    );

    test('fromJson handles legacy single text + missing arrays gracefully', () {
      final json = {'text': 'legacy', 'sender': 'Old', 'is_user': false};
      final msg = ChatMessage.fromJson(json);
      expect(msg.text, 'legacy');
      expect(msg.swipes, ['legacy']);
      expect(msg.swipeIndex, 0);
      expect(msg.swipeDurations, [0]);
    });

    test('fromJson parses swipe_metadata with nulls preserved', () {
      final json = {
        'text': 't',
        'sender': 'S',
        'is_user': true,
        'swipes': ['t', 't2'],
        'swipe_index': 1,
        'swipe_durations': [0, 0],
        'swipe_metadata': [
          null,
          {'k': 9},
        ],
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.swipeMetadata.length, 2);
      expect(msg.swipeMetadata[0], isNull);
      expect(msg.swipeMetadata[1], {'k': 9});
    });
  });
}
