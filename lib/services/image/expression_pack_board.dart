// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/capability/capability.dart';

/// Which screen started a pack. The screen that started it owns its results:
/// the desktop dialog imports its own, and the phone imports the ones it
/// started.
enum PackOrigin { desktop, phone }

/// One pack, as the phone can see it.
class PackRun {
  PackRun({
    required this.session,
    required this.mode,
    required this.origin,
    required this.characterName,
    this.characterId,
    this.replaceExisting = true,
    this.note,
  });

  final ExpressionPackSession session;
  final PackMode mode;
  final PackOrigin origin;
  final String? characterId;
  final String characterName;
  final bool replaceExisting;

  /// A line the phone shows with the pack (that its base was converted).
  final String? note;

  /// How many pictures were imported, or null while none have been.
  int? imported;

  bool importing = false;
}

/// The one pack the phone can see, start, cancel and import. A new pack
/// replaces the last; a phone pack that is replaced or released is disposed
/// (a desktop dialog disposes its own).
class ExpressionPackBoard extends ChangeNotifier {
  PackRun? _run;
  bool _queued = false;
  bool _disposed = false;

  void _changed() {
    if (_queued || _disposed) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (!_disposed) notifyListeners();
    });
  }

  PackRun? get run => _run;

  void publish(PackRun run) {
    final previous = _run;
    previous?.session.removeListener(_changed);
    _run = run;
    run.session.addListener(_changed);
    if (previous != null &&
        previous.origin == PackOrigin.phone &&
        !identical(previous.session, run.session)) {
      previous.session.dispose();
    }
    _changed();
  }

  /// The dialog that owned [session] is closing.
  void release(ExpressionPackSession session) {
    if (identical(_run?.session, session)) {
      session.removeListener(_changed);
      _run = null;
      _changed();
    }
  }

  void clear() {
    final previous = _run;
    previous?.session.removeListener(_changed);
    _run = null;
    if (previous?.origin == PackOrigin.phone) previous!.session.dispose();
    _changed();
  }

  void setImporting(PackRun run, bool importing) {
    run.importing = importing;
    if (identical(_run, run)) _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _run?.session.removeListener(_changed);
    super.dispose();
  }

  /// What the phone is told. Pictures are not in it; each done one has its
  /// own address.
  Map<String, Object?>? view() {
    final run = _run;
    if (run == null) return null;
    final slots = run.session.slots;
    return {
      'running': run.session.isRunning,
      'importing': run.importing,
      'promptRules': run.session.promptRules.toJson(),
      'mode': run.mode.name,
      'origin': run.origin.name,
      'characterId': run.characterId,
      'characterName': run.characterName,
      'replaceExisting': run.replaceExisting,
      'note': run.note,
      'total': slots.length,
      'done': run.session.doneCount,
      'kept': run.session.keptCount,
      'imported': run.imported,
      'canImport':
          run.origin == PackOrigin.phone &&
          run.imported == null &&
          !run.importing &&
          !run.session.isRunning &&
          run.session.keptCount > 0,
      'slots': [
        for (final slot in slots)
          {
            'emotion': slot.emotion,
            'state': slot.state.name,
            'keep': slot.keep,
            'error': slot.error,
            if (slot.qc != null)
              'verdict': {
                'samePerson': slot.qc!.samePerson,
                'expressionMatches': slot.qc!.expressionMatches,
                'note': slot.qc!.note,
              },
          },
      ],
    };
  }

  /// The finished picture for [emotion], or null.
  Uint8List? picture(String emotion) {
    final run = _run;
    if (run == null) return null;
    for (final slot in run.session.slots) {
      if (slot.emotion == emotion &&
          slot.state == ExpressionSlotState.done &&
          slot.bytes != null) {
        return slot.bytes;
      }
    }
    return null;
  }
}

final ExpressionPackBoard expressionPackBoard = ExpressionPackBoard();
