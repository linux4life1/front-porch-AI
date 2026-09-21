// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Context Budget snapshot model + in-memory store. Persisted per chat session
// as sessions.context_budget_json (schema v44). Keeps ChatService thin.

import 'dart:convert';

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

  const ContextViewerSnapshot({
    required this.budget,
    required this.sections,
    this.source = ContextBudgetSource.lastSend,
    this.assembledAt,
    this.contextLimit,
  });

  bool get isEmpty => budget.isEmpty;

  Map<String, dynamic> toJson() => {
    'budget': budget,
    'sections': sections,
    'source': source.name,
    if (assembledAt != null) 'assembledAt': assembledAt!.toIso8601String(),
    if (contextLimit != null) 'contextLimit': contextLimit,
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
    if (budget.isEmpty) return null;

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

/// Live Context Budget state for the open chat.
class ContextBudgetStore {
  Map<String, int> budget = {};
  Map<String, String> sections = const {};
  ContextBudgetSource source = ContextBudgetSource.none;
  DateTime? assembledAt;

  /// Last real send kept even while the UI shows a live estimate, so save
  /// still writes the real send.
  ContextViewerSnapshot? _lastSendSticky;

  bool get isEmpty => budget.isEmpty;

  void clear() {
    budget = {};
    sections = const {};
    source = ContextBudgetSource.none;
    assembledAt = null;
    _lastSendSticky = null;
  }

  void apply(ContextViewerSnapshot snap) {
    budget = Map<String, int>.from(snap.budget);
    sections = Map<String, String>.from(snap.sections);
    source = snap.source;
    assembledAt = snap.assembledAt ?? DateTime.now();
    if (snap.source == ContextBudgetSource.lastSend && !snap.isEmpty) {
      _lastSendSticky = ContextViewerSnapshot(
        budget: Map<String, int>.from(snap.budget),
        sections: Map<String, String>.from(snap.sections),
        source: ContextBudgetSource.lastSend,
        assembledAt: assembledAt,
        contextLimit: snap.contextLimit,
      );
    }
  }

  void recordLastSend({
    required Map<String, int> budgetMap,
    required Map<String, String> sectionMap,
    int? contextLimit,
  }) {
    apply(
      ContextViewerSnapshot(
        budget: budgetMap,
        sections: sectionMap,
        source: ContextBudgetSource.lastSend,
        assembledAt: DateTime.now(),
        contextLimit: contextLimit,
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
  final List<String> historyLines;
  final int contextLimit;

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
  });
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
  if (input.historyLines.isNotEmpty) {
    add('Chat History', '${input.historyLines.join('\n')}\n');
  }

  return ContextViewerSnapshot(
    budget: budget,
    sections: sections,
    source: ContextBudgetSource.estimate,
    assembledAt: DateTime.now(),
    contextLimit: input.contextLimit,
  );
}
