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

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// The Context Viewer's budget for the open chat: the last send's rows and
/// sections (kept per session, saved with it), the live estimate the
/// Refresh button runs without a model call, and the prompt record a reply
/// keeps on its swipe.
class ContextBudget {
  ContextBudget(this._a, this._d);

  final PromptAssembler _a;
  final PromptDeps _d;
  final ContextBudgetStore _contextBudget = ContextBudgetStore();

  /// The live store; the request build records each send into it.
  ContextBudgetStore get store => _contextBudget;

  Map<String, int> get budget => _contextBudget.budget;
  Map<String, String> get sections => _contextBudget.sections;
  ContextBudgetSource get source => _contextBudget.source;
  DateTime? get assembledAt => _contextBudget.assembledAt;
  int get droppedMessages => _contextBudget.droppedMessages;

  ChatSessionState get _session => _d.session;
  AppDatabase get _db => _d.services.db();
  StorageService get _storageService => _d.services.storage;
  UserPersonaService get _userPersonaService => _d.services.personas;
  PromptSource get _source => _a.source;
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  bool get _observerMode => _d.doors.entry().director.observerMode;
  bool get _directing => _d.doors.entry().director.directing;
  String get _authorNote => _d.doors.sessions().authorNote;
  ChatGenerationSettings get _sessionGenSettings =>
      _d.doors.sessions().genSettings;

  void clear() => _contextBudget.clear();

  Future<void> load(String sessionId) async {
    final json = await _db.getContextBudgetJson(sessionId);
    _contextBudget.loadFromJson(json);
  }

  Future<void> persist(String sessionId) async {
    final json = _contextBudget.persistJson(contextLimit: _a.contextSize);
    await _db.setContextBudgetJson(sessionId, json);
  }

  /// Records the send that produced [target] on its shown swipe. A Continue
  /// extends a reply whose prompt is already recorded, so it keeps that one.
  void stampReplyContext(ChatMessage target, {required bool continuing}) {
    if (target.isUser) return;
    if (continuing && target.activeMetadata?[kReplyContextKey] != null) {
      return;
    }
    final send = _contextBudget.lastSend;
    if (send == null || send.isEmpty) return;
    target.activeMetadata ??= {};
    target.activeMetadata![kReplyContextKey] = send.toJson();
    trimReplyContextTexts(_session.messages);
  }

  /// The prompt record of the reply at [index], or null when none was kept.
  ContextViewerSnapshot? replyContextSnapshot(int index) {
    if (index < 0 || index >= _session.messages.length) return null;
    final m = _session.messages[index];
    if (m.isUser) return null;
    return replyContextOf(m);
  }

  /// Live estimate from the open chat (no model call). Context Viewer refresh.
  Future<void> estimateNow() async {
    if (_session.activeCharacter == null && _activeGroup == null) return;

    final identity = StringBuffer();
    var systemPrompt = '';
    var scenario = '';
    var examples = '';
    var postHistory = '';

    var personaBlock = '';
    var speakerCard = '';
    if (_activeGroup != null) {
      final g = _activeGroup!;
      systemPrompt = _source.groupBasePrompt;
      scenario = g.scenario.isNotEmpty
          ? g.scenario
          : (_groupCharacters.isNotEmpty
                ? _groupCharacters.first.scenario
                : '');
      personaBlock = buildGroupRosterLine(
        memberNames: [for (final c in _groupCharacters) c.name],
        userName: _userPersonaService.persona.name,
        observerMode: _observerMode,
        visitorNames: {
          for (final c in _groupCharacters)
            if (c.isLite) c.name,
        },
      );
      final speaker =
          _session.groupManager?.nextSpeaker ??
          (_groupCharacters.isNotEmpty ? _groupCharacters.first : null);
      if (speaker != null) {
        speakerCard = _a.blocks.groupSpeakerCard(
          speaker,
          userName: _userPersonaService.persona.name,
        );
      }
    } else if (_session.activeCharacter != null) {
      final c = _session.activeCharacter!;
      systemPrompt = _source.resolveOneToOneBase(c);
      scenario = c.scenario;
      examples = c.mesExample;
      postHistory = c.postHistoryInstructions;
      final block = [
        if (c.description.trim().isNotEmpty) c.description.trim(),
        if (c.personality.trim().isNotEmpty) c.personality.trim(),
      ].join('\n');
      if (block.isNotEmpty) identity.writeln('${c.name}: $block');
    }

    if (_source.amendmentsAllowed) {
      systemPrompt = _storageService.generationSettings
          .withSystemPromptAddition(systemPrompt);
      postHistory = _storageService.generationSettings.withPostHistoryAddition(
        postHistory,
      );
    }
    if (_activeGroup != null) {
      systemPrompt = withGroupSceneRules(systemPrompt, directing: _directing);
    }

    // The send's own line format (think blocks stripped) and trim rules,
    // so the estimate shows what a send would carry, not the whole chat.
    final historyLines = _session.messages
        .map(_a.history.formatHistoryLine)
        .toList();

    final snap = buildContextBudgetEstimate(
      ContextBudgetEstimateInput(
        userName: _userPersonaService.persona.name,
        userPersonaText: _directing ? '' : _userPersonaService.persona.persona,
        systemPrompt: systemPrompt,
        identityBlock: identity.toString(),
        personaBlock: personaBlock,
        speakerCard: speakerCard,
        scenario: scenario,
        examples: examples,
        postHistory: postHistory,
        authorNote: _authorNote,
        historyLines: historyLines,
        contextLimit: _a.contextSize,
        reserveTokens:
            _sessionGenSettings.resolveMaxLength(_storageService) + 50,
        trimChunk: kHistoryTrimChunk,
        overflowStart: overflowHistoryStart(_session.messages),
      ),
    );

    if (snap.isEmpty) {
      // Keep sticky last-send in the store; only clear the on-screen view if
      // we had nothing else — load sticky back for display if present.
      final stickyJson = _contextBudget.persistJson(
        contextLimit: _a.contextSize,
      );
      if (stickyJson != null) {
        _contextBudget.loadFromJson(stickyJson);
      } else {
        _contextBudget.clear();
      }
      _d.notify();
      return;
    }

    // The same tokenizer the send uses, so Refresh and the last send agree
    // (the fit above stays chars/4; only the rows are re-weighed).
    final estimated = await _a.history.countTokens(snap.sections.values.join());
    _contextBudget.apply(
      ContextViewerSnapshot(
        budget: scaleBudgetRows(snap.budget, estimated),
        sections: snap.sections,
        source: snap.source,
        assembledAt: snap.assembledAt,
        contextLimit: snap.contextLimit,
        droppedMessages: snap.droppedMessages,
      ),
    );
    _d.notify();
  }
}
