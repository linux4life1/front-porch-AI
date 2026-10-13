// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/models.dart';

/// `/director`, the persona's own `/exit me` / `/join me`, and the
/// director's tools: `/whisper`, `/goal` and `/narrate`.
///
/// Director Mode is {{user}} stepping off stage to steer a cast that keeps
/// talking among themselves, so it needs a cast: a group, or a 1:1 with a
/// Scene Guest (which becomes a group first, guests staying Guests — the
/// bare `/promote` path). A plain 1:1 is refused. Every action is an
/// injected callback, like the rest of the command leaves.
class DirectorCommands {
  DirectorCommands({
    required bool Function() isGroup,
    required bool Function() hasSceneGuests,
    required bool Function() isDirecting,
    required Future<void> Function() promoteSceneToGroup,
    required Future<bool> Function() stepUserOffStage,
    required Future<bool> Function() stepUserOnStage,
    required List<CharacterCard> Function() getCast,
    required Future<void> Function(CharacterCard member, String text)
    setWhisper,
    required Future<void> Function(String text) setGoal,
    required Future<bool> Function(String hint) narrate,
    required void Function(String message) onSystemMessage,
  }) : _isGroup = isGroup,
       _hasSceneGuests = hasSceneGuests,
       _isDirecting = isDirecting,
       _promoteSceneToGroup = promoteSceneToGroup,
       _stepUserOffStage = stepUserOffStage,
       _stepUserOnStage = stepUserOnStage,
       _getCast = getCast,
       _setWhisper = setWhisper,
       _setGoal = setGoal,
       _narrate = narrate,
       _say = onSystemMessage;

  final bool Function() _isGroup;
  final bool Function() _hasSceneGuests;
  final bool Function() _isDirecting;
  final Future<void> Function() _promoteSceneToGroup;
  final Future<bool> Function() _stepUserOffStage;
  final Future<bool> Function() _stepUserOnStage;
  final List<CharacterCard> Function() _getCast;
  final Future<void> Function(CharacterCard member, String text) _setWhisper;
  final Future<void> Function(String text) _setGoal;
  final Future<bool> Function(String hint) _narrate;
  final void Function(String message) _say;

  static const _selfTokens = {'me', 'myself', 'you', 'user', '{{user}}'};
  static const _offWords = {
    'off',
    'stop',
    'end',
    'done',
    'exit',
    'leave',
    'return',
    'back',
  };

  /// Whether `/exit` or `/join` args name the user themself.
  static bool namesSelf(String args) =>
      _selfTokens.contains(args.trim().toLowerCase());

  /// Claims `/director`, `/exit me` and `/join me`; anything else is left
  /// to the other command leaves (false).
  Future<bool> tryHandle(String command, String args) async {
    switch (command) {
      case 'director':
        await handleDirector(args);
        return true;
      case 'exit' when namesSelf(args):
        await stepOut();
        return true;
      case 'join' when namesSelf(args):
        await stepIn();
        return true;
      case 'whisper':
        await whisper(args);
        return true;
      case 'goal':
        await goal(args);
        return true;
      case 'narrate':
        await narrate(args);
        return true;
      default:
        return false;
    }
  }

  /// `/director` steps out to direct; `/director off` steps back in.
  Future<void> handleDirector(String args) async {
    final a = args.trim().toLowerCase();
    if (a.isEmpty || a == 'on') return stepOut();
    if (_offWords.contains(a)) return stepIn();
    _say(
      '⚠ Use /director to step out and direct, or /director off to step '
      'back in.',
    );
  }

  Future<void> stepOut() async {
    if (_isDirecting()) {
      _say('You are already directing. /director off steps you back in.');
      return;
    }
    if (!_isGroup()) {
      if (!_hasSceneGuests()) {
        _say(
          '⚠ Director Mode needs a cast to direct. Bring someone in with '
          '/join first.',
        );
        return;
      }
      await _promoteSceneToGroup();
      // The conversion reports its own failure; nothing to direct without it.
      if (!_isGroup()) return;
    }
    if (!await _stepUserOffStage()) {
      _say('⚠ Wait for the current turn to finish, then try again.');
    }
  }

  Future<void> stepIn() async {
    if (!_isDirecting()) {
      _say('⚠ You are already in the scene. /director steps you out.');
      return;
    }
    if (!await _stepUserOnStage()) {
      _say('⚠ Wait for the current turn to finish, then try again.');
    }
  }

  bool _requireDirecting(String command) {
    if (_isDirecting()) return true;
    _say('⚠ /$command works while you direct. Step out with /director first.');
    return false;
  }

  /// `/whisper <name> <direction>` or `/whisper <name> off`.
  Future<void> whisper(String args) async {
    if (!_requireDirecting('whisper')) return;
    final split = splitMemberAndText(args, _getCast());
    if (split == null) {
      final names = _getCast().map((c) => c.name).join(', ');
      _say('⚠ Use /whisper <name> <direction>. In the scene: $names.');
      return;
    }
    final (member, text) = split;
    if (text.isEmpty) {
      _say('⚠ What should ${member.name} know? /whisper ${member.name} …');
      return;
    }
    final clearing = _offWords.contains(text.toLowerCase());
    await _setWhisper(member, clearing ? '' : text);
    _say(
      clearing
          ? 'Whisper to ${member.name} cleared.'
          : 'Only ${member.name} knows this now.',
    );
  }

  /// `/goal <text>` pins a scene goal; `/goal off` clears it.
  Future<void> goal(String args) async {
    if (!_requireDirecting('goal')) return;
    final text = args.trim();
    if (text.isEmpty) {
      _say('⚠ Use /goal <where the scene should go>, or /goal off.');
      return;
    }
    final clearing = _offWords.contains(text.toLowerCase());
    await _setGoal(clearing ? '' : text);
    _say(clearing ? 'Scene goal cleared.' : 'Scene goal pinned.');
  }

  /// `/narrate [what happens]`: a narrator beat, then the cast reacts.
  Future<void> narrate(String args) async {
    if (!_requireDirecting('narrate')) return;
    if (!await _narrate(args.trim())) {
      _say('⚠ Wait for the current turn to finish, then try again.');
    }
  }

  /// The cast member [args] starts with, and the rest of the text. The
  /// longest full name wins ("Mara Vance said…" is Mara Vance, not Mara);
  /// otherwise the first word must match exactly one member.
  static (CharacterCard, String)? splitMemberAndText(
    String args,
    List<CharacterCard> cast,
  ) {
    final a = args.trim();
    final lower = a.toLowerCase();
    final byLength = [...cast]
      ..sort((x, y) => y.name.length.compareTo(x.name.length));
    for (final c in byLength) {
      final n = c.name.trim().toLowerCase();
      if (n.isEmpty) continue;
      if (lower == n) return (c, '');
      if (lower.startsWith('$n ')) return (c, a.substring(n.length).trim());
    }
    final space = a.indexOf(RegExp(r'\s'));
    final first = (space < 0 ? a : a.substring(0, space)).toLowerCase();
    if (first.isEmpty) return null;
    final hits = [
      for (final c in cast)
        if (c.name.toLowerCase().contains(first)) c,
    ];
    if (hits.length != 1) return null;
    return (hits.single, space < 0 ? '' : a.substring(space).trim());
  }
}
