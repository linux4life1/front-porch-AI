// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Context Budget snapshot model + in-memory store. Persisted per chat session
// as sessions.context_budget_json (schema v44). Keeps ChatService thin.

import 'dart:convert';

/// Budget key older saves used for the dropped-message count.
const kLegacyDroppedMessagesKey = 'Dropped Messages';

/// First line of a trimmed Chat History, in the prompt and in the estimate.
const kHistoryTruncatedMarker =
    '[Earlier messages truncated — see the recap below for context]';

/// Where the numbers currently shown in the Context Viewer came from.
enum ContextBudgetSource {
  /// Nothing loaded yet.
  none,

  /// Last real model send for this chat (saved with the session).
  lastSend,

  /// Built on demand from the chat as it sits right now.
  estimate,
}

/// Serializable Context Budget payload (token rows + section texts).
class ContextViewerSnapshot {
  final Map<String, int> budget;
  final Map<String, String> sections;
  final ContextBudgetSource source;
  final DateTime? assembledAt;
  final int? contextLimit;

  /// Oldest messages left out of Chat History to fit [contextLimit]. A
  /// message count, never tokens, so it stays out of [budget].
  final int droppedMessages;

  const ContextViewerSnapshot({
    required this.budget,
    required this.sections,
    this.source = ContextBudgetSource.lastSend,
    this.assembledAt,
    this.contextLimit,
    this.droppedMessages = 0,
  });

  bool get isEmpty => budget.isEmpty;

  Map<String, dynamic> toJson() => {
    'budget': budget,
    'sections': sections,
    'source': source.name,
    if (assembledAt != null) 'assembledAt': assembledAt!.toIso8601String(),
    if (contextLimit != null) 'contextLimit': contextLimit,
    if (droppedMessages > 0) 'droppedMessages': droppedMessages,
  };

  String toJsonString() => jsonEncode(toJson());

  static ContextViewerSnapshot? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final budgetRaw = map['budget'];
    final sectionsRaw = map['sections'];
    if (budgetRaw is! Map) return null;

    final budget = <String, int>{};
    budgetRaw.forEach((k, v) {
      final n = v is num ? v.toInt() : int.tryParse('$v');
      if (n != null && n > 0) budget['$k'] = n;
    });
    // Saves before droppedMessages had its own field kept the count as a
    // budget row, where it read as tokens and inflated the total.
    final legacyDropped = budget.remove(kLegacyDroppedMessagesKey) ?? 0;
    if (budget.isEmpty) return null;
    final droppedRaw = map['droppedMessages'];
    final dropped = droppedRaw is num
        ? droppedRaw.toInt()
        : int.tryParse('${droppedRaw ?? ''}') ?? legacyDropped;

    final sections = <String, String>{};
    if (sectionsRaw is Map) {
      sectionsRaw.forEach((k, v) {
        if (v != null) sections['$k'] = '$v';
      });
    }

    final sourceName = map['source']?.toString();
    var source = ContextBudgetSource.values.firstWhere(
      (s) => s.name == sourceName,
      orElse: () => ContextBudgetSource.lastSend,
    );
    if (source == ContextBudgetSource.none) {
      source = ContextBudgetSource.lastSend;
    }

    DateTime? at;
    final atRaw = map['assembledAt']?.toString();
    if (atRaw != null && atRaw.isNotEmpty) at = DateTime.tryParse(atRaw);

    final limitRaw = map['contextLimit'];
    final limit = limitRaw is num
        ? limitRaw.toInt()
        : int.tryParse('${limitRaw ?? ''}');

    return ContextViewerSnapshot(
      budget: budget,
      sections: sections,
      source: source,
      assembledAt: at,
      contextLimit: limit,
      droppedMessages: dropped < 0 ? 0 : dropped,
    );
  }

  static ContextViewerSnapshot? fromJsonString(String? json) {
    if (json == null || json.isEmpty || json == '{}') return null;
    try {
      return tryParse(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  /// chars/4 token estimate used everywhere in the Context Viewer.
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 4).ceil();
  }

  static void addLabeled({
    required Map<String, int> budget,
    required Map<String, String> sections,
    required String label,
    required String text,
  }) {
    if (label.isEmpty || text.isEmpty) return;
    sections[label] = '${sections[label] ?? ''}$text';
    budget[label] = (budget[label] ?? 0) + estimateTokens(text);
  }
}

/// The viewer's line for [count] oldest messages left out of Chat History.
String droppedMessagesNote(int count) =>
    '$count older message${count == 1 ? '' : 's'} not sent — trimmed to fit '
    'the context.';

/// Live Context Budget state for the open chat.
class ContextBudgetStore {
  Map<String, int> budget = {};
  Map<String, String> sections = const {};
  ContextBudgetSource source = ContextBudgetSource.none;
  DateTime? assembledAt;
  int droppedMessages = 0;

  /// Last real send kept even while the UI shows a live estimate, so save
  /// still writes the real send.
  ContextViewerSnapshot? _lastSendSticky;

  bool get isEmpty => budget.isEmpty;

  /// The last real send, even while the view shows a live estimate.
  ContextViewerSnapshot? get lastSend => _lastSendSticky;

  void clear() {
    budget = {};
    sections = const {};
    source = ContextBudgetSource.none;
    assembledAt = null;
    droppedMessages = 0;
    _lastSendSticky = null;
  }

  void apply(ContextViewerSnapshot snap) {
    budget = Map<String, int>.from(snap.budget);
    sections = Map<String, String>.from(snap.sections);
    source = snap.source;
    assembledAt = snap.assembledAt ?? DateTime.now();
    droppedMessages = snap.droppedMessages;
    if (snap.source == ContextBudgetSource.lastSend && !snap.isEmpty) {
      _lastSendSticky = ContextViewerSnapshot(
        budget: Map<String, int>.from(snap.budget),
        sections: Map<String, String>.from(snap.sections),
        source: ContextBudgetSource.lastSend,
        assembledAt: assembledAt,
        contextLimit: snap.contextLimit,
        droppedMessages: snap.droppedMessages,
      );
    }
  }

  void recordLastSend({
    required Map<String, int> budgetMap,
    required Map<String, String> sectionMap,
    int? contextLimit,
    int droppedMessages = 0,
  }) {
    apply(
      ContextViewerSnapshot(
        budget: budgetMap,
        sections: sectionMap,
        source: ContextBudgetSource.lastSend,
        assembledAt: DateTime.now(),
        contextLimit: contextLimit,
        droppedMessages: droppedMessages,
      ),
    );
  }

  /// JSON to persist (last real send only — never an estimate).
  String? persistJson({int? contextLimit}) {
    final sticky = source == ContextBudgetSource.lastSend && budget.isNotEmpty
        ? ContextViewerSnapshot(
            budget: Map<String, int>.from(budget),
            sections: Map<String, String>.from(sections),
            source: ContextBudgetSource.lastSend,
            assembledAt: assembledAt,
            contextLimit: contextLimit,
            droppedMessages: droppedMessages,
          )
        : _lastSendSticky;
    if (sticky == null || sticky.isEmpty) return null;
    return sticky.toJsonString();
  }

  void loadFromJson(String? json) {
    final snap = ContextViewerSnapshot.fromJsonString(json);
    if (snap == null || snap.isEmpty) {
      clear();
      return;
    }
    apply(
      ContextViewerSnapshot(
        budget: snap.budget,
        sections: snap.sections,
        source: ContextBudgetSource.lastSend,
        assembledAt: snap.assembledAt,
        contextLimit: snap.contextLimit,
        droppedMessages: snap.droppedMessages,
      ),
    );
  }
}

/// Inputs for a live estimate (no model call). Built by ChatService from
/// the open chat; kept free of god-file types where practical.
class ContextBudgetEstimateInput {
  final String userName;
  final String userPersonaText;
  final String systemPrompt;
  final String identityBlock;
  final String personaBlock;
  final String speakerCard;
  final String scenario;
  final String examples;
  final String postHistory;
  final String authorNote;

  /// One prompt line per message, oldest first; blank lines stay so the
  /// dropped count is in messages, as on a real send.
  final List<String> historyLines;
  final int contextLimit;

  /// Tokens a send holds back for the reply (max length plus its margin).
  final int reserveTokens;

  /// A send's drop point is rounded up to this many messages.
  final int trimChunk;

  /// First message a send keeps when nothing but the fixed sections fit.
  final int overflowStart;

  const ContextBudgetEstimateInput({
    this.userName = 'User',
    this.userPersonaText = '',
    this.systemPrompt = '',
    this.identityBlock = '',
    this.personaBlock = '',
    this.speakerCard = '',
    this.scenario = '',
    this.examples = '',
    this.postHistory = '',
    this.authorNote = '',
    this.historyLines = const [],
    this.contextLimit = 0,
    this.reserveTokens = 0,
    this.trimChunk = 1,
    this.overflowStart = 0,
  });
}

/// The history a send would carry: the real walk (newest first, the oldest
/// dropped once the budget is spent, the drop point rounded up to
/// [trimChunk]) at the viewer's chars/4 count. A [budget] of zero or less
/// keeps only the lines from [overflowStart] on, like a send does.
({List<String> kept, int dropped}) fitHistoryEstimate(
  List<String> lines, {
  required int budget,
  int trimChunk = 1,
  int overflowStart = 0,
}) {
  if (budget <= 0) {
    final start = overflowStart.clamp(0, lines.length);
    return (kept: lines.sublist(start), dropped: start);
  }
  var used = 0;
  var dropped = 0;
  var anyKept = false;
  for (var i = lines.length - 1; i >= 0; i--) {
    if (lines[i].isEmpty) continue;
    final tokens = ContextViewerSnapshot.estimateTokens(lines[i]);
    if (used + tokens > budget && anyKept) {
      dropped = i + 1;
      break;
    }
    used += tokens;
    anyKept = true;
  }
  if (dropped > 0 && trimChunk > 1) {
    final rounded = ((dropped + trimChunk - 1) ~/ trimChunk) * trimChunk;
    dropped = rounded.clamp(dropped, lines.length - 1);
  }
  return (kept: lines.sublist(dropped), dropped: dropped);
}

/// Pure estimate builder for the Context Viewer refresh button.
ContextViewerSnapshot buildContextBudgetEstimate(
  ContextBudgetEstimateInput input,
) {
  final budget = <String, int>{};
  final sections = <String, String>{};

  void add(String label, String text) {
    ContextViewerSnapshot.addLabeled(
      budget: budget,
      sections: sections,
      label: label,
      text: text,
    );
  }

  if (input.userPersonaText.trim().isNotEmpty) {
    add(
      'Persona',
      'User (${input.userName}): ${input.userPersonaText.trim()}\n',
    );
  }
  if (input.systemPrompt.trim().isNotEmpty) {
    add('System Prompt', input.systemPrompt);
  }
  if (input.identityBlock.trim().isNotEmpty) {
    add('System Prompt', input.identityBlock);
  }
  if (input.personaBlock.trim().isNotEmpty) {
    add('Persona', input.personaBlock);
  }
  if (input.speakerCard.trim().isNotEmpty) {
    add('Speaker Card', input.speakerCard);
  }
  if (input.scenario.trim().isNotEmpty) add('Scenario', input.scenario);
  if (input.examples.trim().isNotEmpty) add('Examples', input.examples);
  if (input.postHistory.trim().isNotEmpty) {
    add('Post-History', input.postHistory);
  }
  if (input.authorNote.trim().isNotEmpty) {
    add('Post-History', 'Author note: ${input.authorNote.trim()}\n');
  }

  var history = input.historyLines;
  var dropped = 0;
  var marked = false;
  if (input.contextLimit > 0) {
    final fixed = budget.values.fold<int>(0, (a, b) => a + b);
    final room = input.contextLimit - fixed - input.reserveTokens;
    final fit = fitHistoryEstimate(
      history,
      budget: room,
      trimChunk: input.trimChunk,
      overflowStart: input.overflowStart,
    );
    history = fit.kept;
    dropped = fit.dropped;
    // A send marks a budget trim; the overflow floor goes out unmarked.
    marked = room > 0 && dropped > 0;
  }
  final shown = [
    if (marked) kHistoryTruncatedMarker,
    ...history.where((l) => l.isNotEmpty),
  ];
  if (shown.isNotEmpty) add('Chat History', '${shown.join('\n')}\n');

  return ContextViewerSnapshot(
    budget: budget,
    sections: sections,
    source: ContextBudgetSource.estimate,
    assembledAt: DateTime.now(),
    contextLimit: input.contextLimit,
    droppedMessages: dropped,
  );
}
