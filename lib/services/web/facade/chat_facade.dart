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

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_realism_read.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// Thin adapter over [ChatService] for the rewritten web server. Mirrors the
/// legacy chat handlers' JSON contract and pushes a `chat_updated` signal over
/// the WebSocket hub after any state-changing action so clients refetch state.
class ChatFacade {
  ChatFacade(
    this._chat,
    this._characters,
    this._personas,
    this._hub,
    this._groups,
  );

  final ChatService _chat;
  final CharacterRepository _characters;
  final UserPersonaService? _personas;
  final StreamHub? _hub;
  final GroupChatRepository? _groups;

  /// Realism-READ leaf (host snapshot + per-member participant realism). Pure
  /// reads of [ChatService]; co-located 1:1/group parity pair lives there.
  late final ChatRealismRead _realism = ChatRealismRead(_chat);

  /// Full chat state payload (matches legacy `/api/chat/state`).
  Map<String, dynamic> state() {
    final activeChar = _chat.activeCharacter;
    final messages = _chat.messages.asMap().entries.map((e) {
      final m = e.value;
      final chips = _messageChips(m.activeMetadata);
      return {
        'index': e.key,
        'sender': m.sender,
        'text': m.displayText,
        'isUser': m.isUser,
        'hasThinking': m.hasThinking,
        'thinkingContent': m.thinkingContent,
        'thinkingDurationMs': m.thinkingDurationMs,
        'swipeCount': m.swipes.length,
        'swipeIndex': m.swipeIndex,
        'characterId': m.characterId,
        'chips': ?chips,
      };
    }).toList();

    final lorebook = <Map<String, dynamic>>[];
    void addEntries(Iterable<dynamic> entries, String prefix) {
      for (final entry in entries) {
        if (!entry.enabled) continue;
        lorebook.add({
          'key': entry.key,
          'name': prefix.isEmpty
              ? entry.displayName
              : '$prefix: ${entry.displayName}',
          'isTriggered': entry.isTriggered,
          'constant': entry.constant,
          'remainingDepth': entry.remainingDepth,
        });
      }
    }

    if (activeChar?.lorebook != null) {
      addEntries(activeChar!.lorebook!.entries, '');
    }
    if (_chat.isGroupMode) {
      for (final ch in _chat.groupCharacters) {
        if (ch.lorebook != null) addEntries(ch.lorebook!.entries, ch.name);
      }
    }

    return {
      'character': activeChar != null
          ? {'name': activeChar.name, 'id': activeChar.dbId}
          : null,
      // Title for the unified header: group name in a group, else the host name
      // (activeCharacter is null in a group, so the client can't rely on it).
      'chatTitle': _chat.activeGroup?.name ?? activeChar?.name,
      'sessionId': _chat.currentSessionId,
      'sessionName': _chat.sessionName,
      'messages': messages,
      'isGenerating': _chat.isGenerating,
      // Processing-overlay state (mirrors the desktop Realism + Objective engine
      // overlays). The WS pushes a live `processing` event during eval; these
      // fields let a client that connects mid-eval render the overlay too.
      'isEvaluatingRealism': _chat.isEvaluatingRealism,
      'isCheckingCompletion': _chat.isCheckingCompletion,
      'isProcessingGreeting': _chat.isProcessingGreeting,
      'isVerifyingRealism': _chat.isVerifyingRealism,
      'realismEvalText': _chat.realismEvalStreamTextClean,
      'isGroupMode': _chat.isGroupMode,
      'groupId': _chat.activeGroup?.id,
      'groupMembers': _chat.isGroupMode
          ? _chat.groupCharacters
                .map(
                  (c) => {
                    'name': c.name,
                    'charId': c.imagePath != null
                        ? p.basenameWithoutExtension(c.imagePath!)
                        : c.name
                              .replaceAll(RegExp(r'[^\w\s]'), '')
                              .replaceAll(' ', '_'),
                    'hasAvatar': c.imagePath != null && c.imagePath!.isNotEmpty,
                    'dbId': c.dbId,
                  },
                )
                .toList()
          : null,
      'tokensPerSecond': _chat.tokensPerSecond,
      'tokensGenerated': _chat.tokensGenerated,
      'authorNote': _chat.authorNote,
      'authorNoteDepth': _chat.authorNoteStrength,
      'summary': _chat.summary,
      'summaryLastIndex': _chat.summaryLastIndex,
      'summaryPaused': _chat.summaryPaused,
      'isSummaryGenerating': _chat.isSummaryGenerating,
      'greetingIndex': _chat.greetingIndex,
      'totalGreetings': activeChar?.allGreetings.length ?? 1,
      'userPersonaName': _personas?.persona.name ?? 'User',
      'lorebook': lorebook,
      'realism': _realism.snapshot(),
      // Active expression label (mood) so the web client can cache-bust the
      // expression portrait and only refetch when the mood actually changes.
      // Read-only — no reclassification here, so 1:1/group parity is unaffected.
      'expressionLabel': _chat.currentExpressionLabel,
      // Unified participant cast (host + scene guests in 1:1; members in group).
      // The single roster the unified chat UI iterates — no mode branching.
      'cast': _castJson(),
      // Transient scene-guest banner (creating/joining a guest) + a pending
      // "new character detected — add them?" offer, mirroring the desktop.
      'guestActivity': {
        'status': _chat.guestActivityStatus,
        'isError': _chat.guestActivityIsError,
        'busy': _chat.isGuestBusy,
      },
      'pendingDetection': _chat.pendingGuestDetection?.name,
    };
  }

  /// The unified cast as JSON. Each entry carries enough to render a roster
  /// (avatar, role, emotion, next-up) and to scope the sidebar via [id]
  /// (stableGroupId). Avatars resolve to the character endpoint for host/guests
  /// and the group-member endpoint for members.
  List<Map<String, dynamic>> _castJson() {
    final groupId = _chat.activeGroup?.id;
    final nextDbId = _chat.nextCharacter?.dbId;
    final isGroup = _chat.isGroupMode;
    return _chat.cast.map((p) {
      final card = p.card;
      final avatarUrl = (isGroup && groupId != null)
          ? '/api/groups/$groupId/members/${card.dbId}/avatar'
          : '/api/characters/${card.dbId}/avatar';
      return {
        'id': p.id,
        'dbId': card.dbId,
        'name': p.name,
        'isHost': p.isHost,
        'isLite': p.isLite,
        'realismEnabled': p.realismEnabled,
        'emotion': !p.realismEnabled
            ? null
            : (isGroup
                  ? _chat.getEmotionForGroupCharacter(card)
                  : _chat.characterEmotion),
        'isNext': card.dbId != null && card.dbId == nextDbId,
        'hasAvatar': card.imagePath != null && card.imagePath!.isNotEmpty,
        'avatarUrl': avatarUrl,
      };
    }).toList();
  }

  /// Realism for a single cast participant (focus-scoped sidebar). Delegates to
  /// the [ChatRealismRead] leaf, which co-locates the host snapshot and the
  /// per-member branch (the 1:1-vs-group parity pair).
  Map<String, dynamic>? participantRealism(String participantId) =>
      _realism.participantRealism(participantId);

  /// Extract the per-message Realism chip deltas from a message's active-swipe
  /// metadata (the same keys the desktop bubble reads), omitting zeros/empties.
  Map<String, dynamic>? _messageChips(Map<String, dynamic>? md) {
    if (md == null) return null;
    final out = <String, dynamic>{};
    for (final entry in const {
      'bond_delta': 'bondDelta',
      'trust_delta': 'trustDelta',
      'arousal_delta': 'arousalDelta',
    }.entries) {
      final v = md[entry.key];
      if (v is int && v != 0) out[entry.value] = v;
    }
    for (final entry in const {
      'emotion_label': 'emotionLabel',
      'bond_reason': 'bondReason',
      'trust_reason': 'trustReason',
      'time_skip_to': 'timeSkipTo',
      'chance_time_event': 'chanceTimeEvent',
    }.entries) {
      final v = md[entry.key];
      if (v is String && v.isNotEmpty) out[entry.value] = v;
    }
    final needs = md['needs_deltas'];
    if (needs is Map) {
      final nz = <String, dynamic>{};
      needs.forEach((k, v) {
        // NeedsSimulation.computeNeedsDeltasWithReasons stores {delta, reason}
        // per need; tolerate a plain int too. Carry BOTH the signed delta and
        // the reason so the web chip can show the same hover explanation the
        // desktop bubble does. (Map-not-int is why needs chips never rendered
        // on the web before — see the chip parser fix.)
        final delta = v is int
            ? v
            : (v is Map && v['delta'] is int ? v['delta'] as int : 0);
        if (delta == 0) return;
        final reason = (v is Map && v['reason'] is String)
            ? (v['reason'] as String)
            : '';
        nz[k.toString()] = {'delta': delta, 'reason': reason};
      });
      if (nz.isNotEmpty) out['needsDeltas'] = nz;
    }
    // Director-redo affordances (mirrors message_bubble.dart): the message can be
    // reprocessed when it carries a needs snapshot, and reverted when a
    // pre-reprocess stash exists. The client additionally gates "reprocess" on
    // this being the last, non-generating message (it already knows both).
    final rs = md['realism_state'];
    if (rs is Map && rs['needs'] != null) out['needsReprocessable'] = true;
    if (md['needs_deltas_pre_reprocess'] is Map) out['needsRevertable'] = true;
    return out.isEmpty ? null : out;
  }

  /// Select the active character by its DB id. Returns false if not found.
  Future<bool> select(String characterId) async {
    final card = _characters.characters
        .where((c) => c.dbId == characterId)
        .firstOrNull;
    if (card == null) return false;
    await _chat.setActiveCharacter(card);
    _notify();
    return true;
  }

  /// Open a group chat as the active conversation. Returns false if the group
  /// isn't found or groups aren't wired. Mirrors [select] for parity with the
  /// desktop (which loads the group's last session via setActiveGroup).
  Future<bool> selectGroup(String groupId) async {
    final groups = _groups;
    if (groups == null) return false;
    final group = groups.getById(groupId);
    if (group == null) return false;
    await _chat.setActiveGroup(group, groupRepo: groups);
    _notify();
    return true;
  }

  void send(String text) {
    _chat.sendMessage(text);
    _notify();
  }

  void stop() {
    _chat.stopGeneration();
    _notify();
  }

  /// Escape hatch for the realism-processing overlay's "Cancel Realism" button —
  /// aborts an in-flight Realism eval (mirrors the desktop overlay action).
  void cancelRealismEval() {
    _chat.cancelRealismEval();
    _notify();
  }

  void regenerate() {
    _chat.regenerateLastMessage();
    _notify();
  }

  void continueGeneration() {
    _chat.continueGeneration();
    _notify();
  }

  /// Director redo: re-evaluate a message's Needs deltas using the user's
  /// written [critique]. Awaited (it runs LLM evals) so the route can report the
  /// outcome; the new deltas + a pre-reprocess stash land in the message's
  /// metadata, which the next state fetch surfaces as chips. Reuses the existing
  /// ChatService flow — no parallel logic.
  Future<bool> reprocessNeeds(int index, String critique) async {
    final ok = await _chat.manualReprocessNeeds(index, critique);
    _notify();
    return ok;
  }

  /// Restore a message's Needs deltas + live state from the pre-reprocess stash.
  Future<bool> revertNeedsReprocess(int index) async {
    final ok = await _chat.revertNeedsReprocess(index);
    _notify();
    return ok;
  }

  void swipe(int messageIndex, int direction) {
    _chat.swipeMessage(messageIndex, direction);
    _notify();
  }

  void edit(int index, String text) {
    _chat.editMessage(index, text);
    _notify();
  }

  void delete(int index) {
    _chat.deleteMessage(index);
    _notify();
  }

  /// Append a generated image (served at `/api/image/saved/<filename>`) to the
  /// most recent message as inline markdown, so it renders in the conversation —
  /// parity with the desktop chat's inline-image rendering. Reuses the existing
  /// edit path (no new ChatService surface). Returns false when there is no
  /// message to attach to.
  bool insertImage(String filename) {
    final name = filename.trim();
    if (name.isEmpty) return false;
    final messages = _chat.messages;
    if (messages.isEmpty) return false;
    final index = messages.length - 1;
    final current = messages[index].text;
    final markdown = '![generated image](/api/image/saved/$name)';
    final newText = current.isEmpty ? markdown : '$current\n\n$markdown';
    _chat.editMessage(index, newText);
    _notify();
    return true;
  }

  void setAuthorNote(String note, {int? strength}) {
    _chat.setAuthorNote(note, strength: strength);
    _notify();
  }

  /// All user personas (id, label, active flag) for the web persona switcher.
  List<Map<String, dynamic>> personas() {
    final svc = _personas;
    if (svc == null) return const [];
    final activeId = svc.persona.id;
    return svc.personas
        .map(
          (p) => {
            'id': p.id,
            'label': p.displayLabel,
            'name': p.name,
            'active': p.id == activeId,
          },
        )
        .toList();
  }

  /// Switch the active user persona. Returns false if personas aren't wired.
  Future<bool> setPersona(String id) async {
    final svc = _personas;
    if (svc == null) return false;
    await svc.setActivePersona(id);
    _notify();
    return true;
  }

  /// Full persona detail for the editor (text + name/title), or null if absent.
  Map<String, dynamic>? personaDetail(String id) {
    final svc = _personas;
    if (svc == null) return null;
    for (final p in svc.personas) {
      if (p.id == id) {
        return {
          'id': p.id,
          'title': p.title,
          'name': p.name,
          'persona': p.persona,
        };
      }
    }
    return null;
  }

  /// Create a new persona (and make it active, matching the desktop). Returns
  /// false if personas aren't wired.
  Future<bool> createPersona(Map<String, dynamic> f) async {
    final svc = _personas;
    if (svc == null) return false;
    await svc.createPersona(
      f['title']?.toString() ?? '',
      f['name']?.toString() ?? 'User',
      f['persona']?.toString() ?? '',
      null,
    );
    _notify();
    return true;
  }

  /// Edit an existing persona's text fields (only provided keys change).
  Future<bool> updatePersona(String id, Map<String, dynamic> f) async {
    final svc = _personas;
    if (svc == null) return false;
    UserPersona? existing;
    for (final p in svc.personas) {
      if (p.id == id) {
        existing = p;
        break;
      }
    }
    if (existing == null) return false;
    await svc.updatePersona(
      existing.copyWith(
        title: f.containsKey('title') ? f['title']?.toString() : null,
        name: f.containsKey('name') ? f['name']?.toString() : null,
        persona: f.containsKey('persona') ? f['persona']?.toString() : null,
      ),
    );
    _notify();
    return true;
  }

  /// Delete a persona. The service refuses to delete the last one (throws),
  /// which we surface as false. Returns false if personas aren't wired.
  Future<bool> deletePersona(String id) async {
    final svc = _personas;
    if (svc == null) return false;
    try {
      await svc.deletePersona(id);
    } catch (_) {
      return false;
    }
    _notify();
    return true;
  }

  /// All saved conversations for the currently-active character/group, newest
  /// first — so the web UI can list past chats and let the user resume any of
  /// them via [session]. Reuses ChatService's own session lister; only adapts
  /// the `date` field to a JSON-safe ISO string.
  Future<List<Map<String, dynamic>>> sessions() async {
    final raw = await _chat.getSessions();
    return raw.map((s) {
      final date = s['date'];
      return {...s, 'date': date is DateTime ? date.toIso8601String() : date};
    }).toList();
  }

  /// New chat or load an existing session. Returns the resulting session id.
  Future<String?> session({String? action, String? sessionId}) async {
    if (action == 'new') {
      await _chat.startNewChat();
    } else if (sessionId != null) {
      await _chat.loadSession(sessionId);
    } else {
      return null;
    }
    _notify();
    return _chat.currentSessionId;
  }

  String? get currentSessionId => _chat.currentSessionId;

  void _notify() => _hub?.broadcastChatUpdate();
}
