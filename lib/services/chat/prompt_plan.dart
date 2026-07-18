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

/// The prompt "wheel hub" (docs/design/prompt-state-injection.md §7).
///
/// Before this existed, `_generateResponse` maintained THREE hand-synced
/// copies of the prompt's structure — a `fixedContent` string for token
/// counting, the final `prompt`/`chatSystemPrompt` strings for sending, and a
/// hand-built `_lastPromptBudget` map for the Context Viewer — and every new
/// feature had to be bolted into all three in exactly the right spot (they
/// had already drifted subtly apart once). A [PromptPlan] is the single
/// ordered list of named sections; the system message, the user message, the
/// fixed-count text, and the budget map are all RENDERED from that one list,
/// so a section is either registered as a spoke of the wheel or it does not
/// exist anywhere.
///
/// Rendering is plain concatenation in insertion order — sections carry their
/// own trailing newlines exactly as the old hand-built strings did, so a
/// faithfully-ordered plan renders byte-identical output to the legacy
/// assembly (locked by tests).
///
/// ## The rendered × counted matrix (read before adding a section)
///
/// | rendered | counted | Meaning                | Use                        |
/// |----------|---------|------------------------|----------------------------|
/// | true     | true    | on the wire + in the   | DEFAULT — every static     |
/// |          |         | fixed-token count      | block                      |
/// | true     | false   | on the wire, budget-   | history, memories, idle    |
/// |          |         | fitted separately      | cue ONLY — forgetting      |
/// |          |         |                        | counted:false on a new     |
/// |          |         |                        | budget-fitted section      |
/// |          |         |                        | double-counts and STARVES  |
/// |          |         |                        | history                    |
/// | false    | true    | paid for in fixed, but | @depth lore ONLY: it is    |
/// |          |         | delivered via another  | spliced INTO the history   |
/// |          |         | channel                | lines by the budget walk,  |
/// |          |         |                        | which must NEVER re-count  |
/// |          |         |                        | it (double-pay)            |
/// | false    | false   | ghost — silent no-op   | never legitimate           |
///
/// Late mutation contract: `fixedCountText` is counted ONCE (before the
/// history walk). Sections filled or zeroed afterwards (history, memories,
/// idle cue, the continue-mode zeroing) deliberately do NOT re-enter that
/// count — Continue keeps budgeting as if its stripped blocks were present,
/// exactly as the legacy assembly did.
class PromptSection {
  /// Stable identifier (e.g. 'history', 'memories', 'lore.depth').
  final String id;

  /// Context Viewer label. Sections sharing a label are summed into one
  /// budget row (the lorebook buckets all report as 'Lorebook'). Empty label
  /// = never shown in the budget map.
  final String label;

  /// Rendered into the system message (true) or the user message (false).
  final bool inSystem;

  /// Rendered into the outgoing prompt at all. False = count-only: the text
  /// reaches the model through some other channel (the @depth lore entries
  /// are spliced INTO the history lines) but must still be paid for in the
  /// fixed-token count.
  final bool rendered;

  /// Included in [PromptPlan.fixedCountText] (the "everything except the
  /// budget-fitted sections" text whose token count determines the history
  /// budget). History and retrieved memories are counted by their own
  /// budgeting instead.
  final bool counted;

  String text;

  PromptSection({
    required this.id,
    required this.text,
    this.label = '',
    this.inSystem = false,
    this.rendered = true,
    this.counted = true,
  });
}

class PromptPlan {
  final List<PromptSection> _sections = [];

  /// Register a section (insertion order IS render order). Returns it so
  /// late-filled sections (history, memories, idle cue) can be mutated after
  /// budgeting without re-finding them.
  ///
  /// Throws [StateError] on a duplicate id IN ALL BUILD MODES (not an
  /// assert): a silent duplicate would double-render on the wire and
  /// double-count the budget while `section(id)` mutated only the first
  /// copy — the worst failure class this hub exists to prevent.
  PromptSection add({
    required String id,
    required String text,
    String label = '',
    bool inSystem = false,
    bool rendered = true,
    bool counted = true,
  }) {
    if (_sections.any((s) => s.id == id)) {
      throw StateError('duplicate prompt section id: $id');
    }
    final s = PromptSection(
      id: id,
      text: text,
      label: label,
      inSystem: inSystem,
      rendered: rendered,
      counted: counted,
    );
    _sections.add(s);
    return s;
  }

  PromptSection section(String id) =>
      _sections.firstWhere((s) => s.id == id);

  String _join(bool Function(PromptSection) where) =>
      _sections.where(where).map((s) => s.text).join();

  /// The 'system' role message content.
  String get systemText => _join((s) => s.inSystem && s.rendered);

  /// The 'user' role message content (the transcript + tail blocks).
  String get userText => _join((s) => !s.inSystem && s.rendered);

  /// Everything that participates in the fixed-token count that determines
  /// the history budget (includes count-only sections like @depth lore;
  /// excludes history/memories, which are budget-fitted afterwards).
  String get fixedCountText => _join((s) => s.counted);

  /// Full prompt for the Context Viewer ("always show full prompt").
  String get fullText => '$systemText\n$userText';

  /// Context Viewer budget rows: label → estimated tokens (chars/4, the
  /// viewer's historical estimator), sections sharing a label summed,
  /// zero-size and unlabeled rows dropped.
  Map<String, int> budgetEstimates() {
    final byLabel = <String, int>{};
    for (final s in _sections) {
      if (s.label.isEmpty || s.text.isEmpty) continue;
      byLabel[s.label] = (byLabel[s.label] ?? 0) + s.text.length;
    }
    return {
      for (final e in byLabel.entries)
        if (e.value > 0) e.key: (e.value / 4).ceil(),
    };
  }
}
