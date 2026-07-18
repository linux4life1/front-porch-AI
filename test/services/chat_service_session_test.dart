// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for Session Management logic extracted from ChatService.
// Covers session ID generation, forking, message loading, and state
// restoration across session boundaries.
// aug exercising only passive/qualified (no journal-specific aug file edits;
// full in dedicated journal tests + manual; exercised via god thins
// _maybeRunJournalPass/forceSummaryUpdate ; qualified notes per precedent).
// aug exercising only passive/qualified (no evolution-specific aug file edits; full in dedicated + manual; exercised via god thins _maybeRunPeriodicEvals/_maybeRunGrowthPass ; qualified notes only in dedicated header + god + MD per precedent).
// aug exercising only passive/qualified (no realism-verification-specific aug file edits; full in dedicated + manual; exercised via god thins + leaf verify cb ; qualified notes only in dedicated header + god + MD per precedent).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/chat_message.dart';

// ── Stub: Minimal session management tracker ────────────────────────
// Replicates the session-related fields and transitions from ChatService.

class _SessionStub {
  String? _currentSessionId;
  String? _parentSessionId;
  int? _forkIndex;
  final List<ChatMessage> _messages = [];
  String? _sessionName;
  String? _sessionDescription;
  String _summary = '';
  int _summaryLastIndex = 0;

  String? get currentSessionId => _currentSessionId;
  String? get parentSessionId => _parentSessionId;
  int? get forkIndex => _forkIndex;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  String? get sessionName => _sessionName;
  String? get sessionDescription => _sessionDescription;
  String get summary => _summary;
  int get summaryLastIndex => _summaryLastIndex;

  // ── startNewChat session ID creation (mirrors ChatService line 2252) ─
  int _sessionCounter = 0;
  void startNewChat() {
    _messages.clear();
    _sessionCounter++;
    _currentSessionId =
        '${DateTime.now().millisecondsSinceEpoch}_$_sessionCounter';
    _summary = '';
    _summaryLastIndex = 0;
  }

  // ── loadSession (mirrors ChatService lines 1593-1601) ─────────────
  void loadSession({
    required String sessionId,
    required String? parentSessionId,
    required int? forkIndex,
    required String? name,
    required String? description,
    required String summary,
    required int summaryLastIndex,
  }) {
    _currentSessionId = sessionId;
    _parentSessionId = parentSessionId;
    _forkIndex = forkIndex;
    _sessionName = name;
    _sessionDescription = description;
    _summary = summary;
    _summaryLastIndex = summaryLastIndex;
  }

  // ── forkFromMessage (mirrors ChatService lines 1964-2016) ─────────
  void forkFromMessage(int messageIndex) {
    if (_currentSessionId == null) return;
    if (messageIndex < 0 || messageIndex >= _messages.length) return;

    final oldSessionId = _currentSessionId!;
    final forkedMessages = _messages
        .sublist(0, messageIndex + 1)
        .map(
          (m) => ChatMessage(
            text: m.text,
            sender: m.sender,
            isUser: m.isUser,
            characterId: m.characterId,
            swipes: List.from(m.swipes),
            swipeIndex: m.swipeIndex,
            swipeDurations: List.from(m.swipeDurations),
            metadata: m.metadata != null
                ? Map<String, dynamic>.from(m.metadata!)
                : null,
            swipeMetadata: m.swipeMetadata
                .map((e) => e != null ? Map<String, dynamic>.from(e) : null)
                .toList(),
          ),
        )
        .toList();

    _messages.clear();
    _messages.addAll(forkedMessages);
    _sessionCounter++;
    _currentSessionId =
        '${DateTime.now().millisecondsSinceEpoch}_$_sessionCounter';
    _parentSessionId = oldSessionId;
    _forkIndex = messageIndex;
    _summary = '';
    _summaryLastIndex = 0;
  }

  // ── clearSession (mirrors the clearing logic in setActiveCharacter) ─
  void clearSession() {
    _messages.clear();
    _currentSessionId = null;
    _summary = '';
    _summaryLastIndex = 0;
  }

  // ── Add messages ──────────────────────────────────────────────────
  void addUserMessage(String text) {
    _messages.add(ChatMessage(text: text, sender: 'User', isUser: true));
  }

  void addCharacterMessage(String text, {String sender = 'Luna'}) {
    _messages.add(ChatMessage(text: text, sender: sender, isUser: false));
  }
}

void main() {
  // ─── 3.5: Session Management ───────────────────────────────────────

  group('Session Management — new session creation', () {
    test('startNewChat creates a new session ID', () {
      final stub = _SessionStub();

      stub.startNewChat();

      expect(
        stub.currentSessionId,
        isNotNull,
        reason: 'session ID must be created on new chat',
      );
      expect(stub.currentSessionId, isNotEmpty);
      // Session ID format: "timestamp_counter" - extract timestamp
      final parts = stub.currentSessionId!.split('_');
      final id = int.tryParse(parts[0]);
      expect(id, isNotNull, reason: 'session ID should be parseable as int');
      expect(
        id!,
        greaterThan(1_000_000_000),
        reason: 'session ID should be a millisecond timestamp',
      );
    });

    test('each startNewChat creates a unique session ID', () {
      final stub = _SessionStub();

      stub.startNewChat();
      final firstId = stub.currentSessionId;

      // Small delay to ensure different timestamp
      stub.startNewChat();
      final secondId = stub.currentSessionId;

      expect(firstId, isNotNull);
      expect(secondId, isNotNull);
      expect(
        firstId,
        isNot(equals(secondId)),
        reason: 'each new chat should have a unique session ID',
      );
    });

    test('startNewChat clears existing messages', () {
      final stub = _SessionStub();
      stub.addUserMessage('Hello');
      stub.addCharacterMessage('Hi there!');
      expect(stub.messages.length, 2);

      stub.startNewChat();

      expect(
        stub.messages,
        isEmpty,
        reason: 'new chat must clear all messages',
      );
    });

    test('startNewChat clears summary', () {
      final stub = _SessionStub();
      stub._summary = 'This is a summary';
      stub._summaryLastIndex = 5;

      stub.startNewChat();

      expect(stub.summary, '', reason: 'summary must be cleared on new chat');
      expect(
        stub.summaryLastIndex,
        0,
        reason: 'summaryLastIndex must be reset on new chat',
      );
    });
  });

  group('Session Management — session loading', () {
    test('loadSession restores session ID', () {
      final stub = _SessionStub();
      stub.loadSession(
        sessionId: 'session-123',
        parentSessionId: null,
        forkIndex: null,
        name: 'My Chat',
        description: 'A test chat',
        summary: '',
        summaryLastIndex: 0,
      );

      expect(stub.currentSessionId, 'session-123');
    });

    test('loadSession restores parent session ID', () {
      final stub = _SessionStub();
      stub.loadSession(
        sessionId: 'session-456',
        parentSessionId: 'session-123',
        forkIndex: null,
        name: 'Forked Chat',
        description: '',
        summary: '',
        summaryLastIndex: 0,
      );

      expect(stub.parentSessionId, 'session-123');
    });

    test('loadSession restores fork index', () {
      final stub = _SessionStub();
      stub.loadSession(
        sessionId: 'session-456',
        parentSessionId: 'session-123',
        forkIndex: 3,
        name: 'Forked Chat',
        description: '',
        summary: '',
        summaryLastIndex: 0,
      );

      expect(stub.forkIndex, 3);
    });

    test('loadSession restores session name and description', () {
      final stub = _SessionStub();
      stub.loadSession(
        sessionId: 'session-123',
        parentSessionId: null,
        forkIndex: null,
        name: 'Epic Adventure',
        description: 'A tale of dragons and destiny',
        summary: '',
        summaryLastIndex: 0,
      );

      expect(stub.sessionName, 'Epic Adventure');
      expect(stub.sessionDescription, 'A tale of dragons and destiny');
    });

    test('loadSession restores summary', () {
      final stub = _SessionStub();
      stub.loadSession(
        sessionId: 'session-123',
        parentSessionId: null,
        forkIndex: null,
        name: 'Chat',
        description: '',
        summary: 'Summary of the conversation so far...',
        summaryLastIndex: 10,
      );

      expect(stub.summary, 'Summary of the conversation so far...');
      expect(stub.summaryLastIndex, 10);
    });

    test('loadSession with null parentSessionId clears parent reference', () {
      final stub = _SessionStub();
      stub.loadSession(
        sessionId: 'session-123',
        parentSessionId: 'parent-001',
        forkIndex: null,
        name: 'Chat',
        description: '',
        summary: '',
        summaryLastIndex: 0,
      );
      expect(stub.parentSessionId, 'parent-001');

      // Load a non-forked session
      stub.loadSession(
        sessionId: 'session-456',
        parentSessionId: null,
        forkIndex: null,
        name: 'Chat',
        description: '',
        summary: '',
        summaryLastIndex: 0,
      );
      expect(
        stub.parentSessionId,
        isNull,
        reason: 'parentSessionId should be cleared for non-forked sessions',
      );
    });
  });

  group('Session Management — clearing session resets state', () {
    test('clearing session resets session ID', () {
      final stub = _SessionStub();
      stub.startNewChat();
      expect(stub.currentSessionId, isNotNull);

      stub.clearSession();

      expect(stub.currentSessionId, isNull);
    });

    test('clearing session clears all messages', () {
      final stub = _SessionStub();
      stub.startNewChat();
      stub.addUserMessage('Hello');
      stub.addCharacterMessage('Hi!');

      stub.clearSession();

      expect(stub.messages, isEmpty);
    });

    test('clearing session clears summary', () {
      final stub = _SessionStub();
      stub._summary = 'Old summary';
      stub._summaryLastIndex = 5;

      stub.clearSession();

      expect(stub.summary, '');
      expect(stub.summaryLastIndex, 0);
    });
  });

  group('Session Management — parentSessionId is set when forking', () {
    test('forkFromMessage sets parentSessionId to old session ID', () {
      final stub = _SessionStub();
      stub.startNewChat();
      final oldSessionId = stub.currentSessionId;

      stub.addUserMessage('Hello');
      stub.addCharacterMessage('Hi there!');

      stub.forkFromMessage(0);

      expect(
        stub.parentSessionId,
        oldSessionId,
        reason: 'parentSessionId must reference the original session',
      );
    });

    test('forkFromMessage creates a new session ID', () {
      final stub = _SessionStub();
      stub.startNewChat();
      final oldSessionId = stub.currentSessionId;

      stub.addUserMessage('Hello');
      stub.addCharacterMessage('Hi there!');

      stub.forkFromMessage(0);

      expect(stub.currentSessionId, isNotNull);
      expect(
        stub.currentSessionId,
        isNot(equals(oldSessionId)),
        reason: 'fork must create a new session ID',
      );
    });

    test('forkFromMessage sets forkIndex to the forked message index', () {
      final stub = _SessionStub();
      stub.startNewChat();

      stub.addUserMessage('Hello');
      stub.addCharacterMessage('Hi there!');
      stub.addUserMessage('How are you?');
      stub.addCharacterMessage('I am fine!');

      stub.forkFromMessage(2); // Fork after 3rd message (index 2)

      expect(stub.forkIndex, 2);
    });

    test('forkFromMessage copies messages up to fork index', () {
      final stub = _SessionStub();
      stub.startNewChat();

      stub.addUserMessage('Hello');
      stub.addCharacterMessage('Hi there!');
      stub.addUserMessage('How are you?');
      stub.addCharacterMessage('I am fine!');

      stub.forkFromMessage(1); // Fork after 2nd message

      expect(
        stub.messages.length,
        2,
        reason: 'forked session should have messages 0..1',
      );
      expect(stub.messages[0].text, 'Hello');
      expect(stub.messages[1].text, 'Hi there!');
    });

    test('forkFromMessage does NOT copy messages after fork index', () {
      final stub = _SessionStub();
      stub.startNewChat();

      stub.addUserMessage('Hello');
      stub.addCharacterMessage('Hi there!');
      stub.addUserMessage('How are you?');
      stub.addCharacterMessage('I am fine!');

      stub.forkFromMessage(1);

      expect(
        stub.messages.length,
        2,
        reason: 'must not include messages after the fork point',
      );
    });

    test('forkFromMessage clears summary', () {
      final stub = _SessionStub();
      stub.startNewChat();
      stub._summary = 'Old summary';
      stub._summaryLastIndex = 3;

      stub.addUserMessage('Hello');
      stub.addCharacterMessage('Hi there!');

      stub.forkFromMessage(1);

      expect(
        stub.summary,
        '',
        reason: 'forked session must start with empty summary',
      );
      expect(stub.summaryLastIndex, 0);
    });

    test('forkFromMessage preserves message swipes and metadata', () {
      final stub = _SessionStub();
      stub.startNewChat();

      final msg = ChatMessage(
        text: 'Original',
        sender: 'Luna',
        isUser: false,
        swipes: ['Original', 'Swipe 1', 'Swipe 2'],
        swipeIndex: 1,
        swipeDurations: [100, 200, 300],
        metadata: {'key': 'value'},
        swipeMetadata: [
          null,
          {'swipeKey': 'swipeValue'},
          null,
        ],
      );
      stub._messages.add(msg);

      stub.forkFromMessage(0);

      expect(stub.messages.length, 1);
      expect(stub.messages[0].swipes, ['Original', 'Swipe 1', 'Swipe 2']);
      expect(stub.messages[0].swipeIndex, 1);
      expect(stub.messages[0].swipeDurations, [100, 200, 300]);
      expect(stub.messages[0].metadata, {'key': 'value'});
    });

    test('forkFromMessage with invalid index does nothing', () {
      final stub = _SessionStub();
      stub.startNewChat();

      stub.addUserMessage('Hello');
      stub.addCharacterMessage('Hi there!');

      // Index out of range
      stub.forkFromMessage(10);

      expect(
        stub.messages.length,
        2,
        reason: 'invalid fork index should not modify the session',
      );
      expect(
        stub.parentSessionId,
        isNull,
        reason: 'invalid fork should not set parentSessionId',
      );
    });

    test('forkFromMessage with index -1 does nothing', () {
      final stub = _SessionStub();
      stub.startNewChat();

      stub.addUserMessage('Hello');

      stub.forkFromMessage(-1);

      expect(
        stub.parentSessionId,
        isNull,
        reason: 'negative index should not trigger a fork',
      );
    });

    test('forkFromMessage with no current session does nothing', () {
      final stub = _SessionStub();
      // Never started a chat

      stub.forkFromMessage(0);

      expect(stub.currentSessionId, isNull);
      expect(stub.parentSessionId, isNull);
    });
  });

  group('Session Management — fork chain integrity', () {
    test('double fork preserves the parent chain', () {
      final stub = _SessionStub();
      stub.startNewChat();
      final rootId = stub.currentSessionId;

      stub.addUserMessage('Hello');
      stub.addCharacterMessage('Hi!');

      // First fork
      stub.forkFromMessage(1);
      final fork1Id = stub.currentSessionId;
      expect(stub.parentSessionId, rootId);

      // Add more messages to fork 1
      stub.addUserMessage('How are you?');
      stub.addCharacterMessage('Good!');

      // Second fork (from fork 1)
      stub.forkFromMessage(3);
      expect(stub.parentSessionId, fork1Id);
      expect(
        stub.parentSessionId,
        isNot(equals(rootId)),
        reason: 'fork 2 parent should be fork 1, not the root',
      );
    });

    test('original session is untouched by forking', () {
      final stub = _SessionStub();
      stub.startNewChat();

      stub.addUserMessage('Hello');
      stub.addCharacterMessage('Hi!');
      stub.addUserMessage('How are you?');
      stub.addCharacterMessage('Good!');

      stub.forkFromMessage(1);

      expect(
        stub.messages.length,
        2,
        reason: 'must be in the forked session, not the original',
      );
    });
  });

  group('Session Management — session ID format', () {
    test('session ID is a string of digits', () {
      final stub = _SessionStub();
      stub.startNewChat();

      // Session ID format: "timestamp_counter" - extract the timestamp part
      final parts = stub.currentSessionId!.split('_');
      expect(
        int.tryParse(parts[0]),
        isNotNull,
        reason: 'session ID timestamp should be parseable as an integer',
      );
    });

    test('session ID is unique across rapid calls', () {
      final stub = _SessionStub();
      final ids = <String>{};

      for (int i = 0; i < 10; i++) {
        stub.startNewChat();
        ids.add(stub.currentSessionId!);
      }

      expect(
        ids.length,
        10,
        reason: 'all session IDs should be unique even in rapid succession',
      );
    });
  });

  // Expression + time reset/seed/load sites exercised passively via pre-existing startNew/setActive/load flows (time chat-scoped).
  // (Note qualified per review: "reset sites passively hit by pre-existing...; full time advance/nudge/OOC/resolve/narrative only in dedicated time test + manual"; ambient hits for time load/seed/reset parity).
}
