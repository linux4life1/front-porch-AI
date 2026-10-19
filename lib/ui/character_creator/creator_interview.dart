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

import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'package:front_porch_ai/services/chargen/chargen.dart';

/// One row of the Interview card: a stable [id] (the reorder key), the
/// question it stands for and the box that shows it.
class InterviewRow {
  InterviewRow(this.id, this.q, this.c);

  final int id;
  InterviewQuestion q;
  final TextEditingController c;
}

/// The Interview card's list (docs/design/creator-interview-questions.md):
/// the questions one run asks, as the user left them. Held by
/// `CreatorState`, which saves and notifies; the card calls these.
///
/// The questions are the source of truth; the boxes only show them. An
/// unedited standard row's box is rendered for the voice ([applyVoice]),
/// and the run renders it again from its key, so a stale box never reaches
/// the model.
///
/// [skipped] is the card's "Interview this character" switch. A skipped
/// run asks nothing while the rows stay exactly as they were, so the switch
/// back on restores the list; editing or adding a row turns the interview
/// back on itself.
class CreatorInterview {
  CreatorInterview() {
    _rows.addAll(_rowsFor(standardInterviewQuestions()));
  }

  final List<InterviewRow> _rows = [];
  int _nextId = 0;
  NarrativeVoice _voice = NarrativeVoice.defaults;
  NarrativePronouns _pronouns = NarrativePronouns.they;
  String _voiceKey = '';

  /// The card's switch: on means the run asks none of the rows, while the
  /// rows themselves stay exactly as they were.
  bool skipped = false;

  List<InterviewRow> get rows => List.unmodifiable(_rows);

  /// The eleven standard rows, in order, none edited.
  bool get isStandard {
    if (_rows.length != kStandardInterviewKeys.length) return false;
    for (var i = 0; i < _rows.length; i++) {
      final q = _rows[i].q;
      if (q.key != kStandardInterviewKeys[i] || q.text != null) return false;
    }
    return true;
  }

  bool get atCap => _rows.length >= kInterviewQuestionCap;

  /// What a run is given: `[]` for a skipped interview — the rows stay
  /// underneath so switching back on restores them — else null for the
  /// untouched standard set.
  List<InterviewQuestion>? get forRun => skipped ? const [] : forTemplate;

  /// The rows as a template and the prefs hold them: null for the
  /// untouched standard set, kept whole while [skipped] hides them.
  List<InterviewQuestion>? get forTemplate =>
      isStandard ? null : [for (final r in _rows) r.q];

  /// Re-renders the boxes of unedited standard rows for [voice]. A call
  /// with the voice already shown changes nothing.
  void applyVoice(NarrativeVoice voice, NarrativePronouns pronouns) {
    _voice = voice;
    _pronouns = pronouns;
    final key =
        '${voice.perspective.name}/${voice.tense.name}/${pronouns.subject}';
    if (key == _voiceKey) return;
    _voiceKey = key;
    for (final r in _rows) {
      if (r.q.isStandard && !r.q.isEdited) r.c.text = _textOf(r.q);
    }
  }

  /// The user typed [text] into row [i]. A standard row is kept as written
  /// from now on, even when typed back to the standard words: Reset is the
  /// way back. Typing into a skipped card means the user wants the answer:
  /// the interview turns itself back on.
  void edit(int i, String text) {
    skipped = false;
    final r = _rows[i];
    r.q = r.q.withText(text);
    if (r.c.text != text) r.c.text = text;
  }

  /// False for a conditional row: those are asked only when their setting
  /// holds, and cannot be removed.
  bool remove(int i) {
    if (_rows[i].q.isConditional) return false;
    _disposeAfterFrame([_rows.removeAt(i).c]);
    return true;
  }

  /// A blank custom row at the end; the interview turns itself back on, so
  /// the row a user adds is actually asked. False at the cap.
  bool add() {
    if (atCap) return false;
    skipped = false;
    _rows.add(_row(const InterviewQuestion(text: '')));
    return true;
  }

  /// [newIndex] is where the row lands once it is out of [oldIndex]
  /// (`ReorderableListView.onReorderItem`).
  void move(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    _rows.insert(newIndex, _rows.removeAt(oldIndex));
  }

  /// The eleven standard rows, every custom row and edit dropped, the
  /// switch back on: a reset card asks the standard interview.
  void reset() {
    skipped = false;
    _replace(standardInterviewQuestions());
  }

  /// `''` for the standard set, else the rows as JSON.
  String toPrefs() => isStandard
      ? ''
      : jsonEncode(InterviewQuestion.listToJson([for (final r in _rows) r.q]));

  /// A template's rows: null is the standard set.
  void restoreList(List<InterviewQuestion>? qs) =>
      qs == null ? reset() : _replace(qs);

  /// Reads what [toPrefs] wrote. Empty is the standard set; unreadable
  /// JSON is logged and gives the standard set.
  void restore(String raw) {
    if (raw.trim().isEmpty) {
      reset();
      return;
    }
    try {
      final list = InterviewQuestion.listFromJson(jsonDecode(raw));
      if (list == null) throw const FormatException('not a list');
      _replace(list);
    } catch (e) {
      debugPrint(
        'CharacterCreator: saved interview questions unreadable, using the '
        'standard set: $e',
      );
      reset();
    }
  }

  void dispose() {
    for (final r in _rows) {
      r.c.dispose();
    }
    _rows.clear();
  }

  String _textOf(InterviewQuestion q) =>
      interviewQuestionText(q, voice: _voice, pronouns: _pronouns);

  InterviewRow _row(InterviewQuestion q) =>
      InterviewRow(_nextId++, q, TextEditingController(text: _textOf(q)));

  List<InterviewRow> _rowsFor(List<InterviewQuestion> qs) => [
    for (final q in qs) _row(q),
  ];

  /// New rows with new ids, so every box is rebuilt. The old boxes may
  /// still be on screen this frame.
  void _replace(List<InterviewQuestion> qs) {
    final old = [for (final r in _rows) r.c];
    _rows
      ..clear()
      ..addAll(_rowsFor(qs));
    _disposeAfterFrame(old);
  }

  void _disposeAfterFrame(List<TextEditingController> old) {
    if (old.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }
}
