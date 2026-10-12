// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// `/director` and the persona's own `/exit me` / `/join me`.
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
    required void Function(String message) onSystemMessage,
  }) : _isGroup = isGroup,
       _hasSceneGuests = hasSceneGuests,
       _isDirecting = isDirecting,
       _promoteSceneToGroup = promoteSceneToGroup,
       _stepUserOffStage = stepUserOffStage,
       _stepUserOnStage = stepUserOnStage,
       _say = onSystemMessage;

  final bool Function() _isGroup;
  final bool Function() _hasSceneGuests;
  final bool Function() _isDirecting;
  final Future<void> Function() _promoteSceneToGroup;
  final Future<bool> Function() _stepUserOffStage;
  final Future<bool> Function() _stepUserOnStage;
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
}
