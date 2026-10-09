// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/chat/chat.dart';

/// Where the wizard stands on "can this model use tools?". It reads chat's
/// own tool check (the sidebar's Tool calling pill), never a guess.
enum WorldToolsGate {
  /// The check passed: the wizard may run.
  ready,

  /// The check is asking the model right now.
  checking,

  /// Nothing has been asked yet and the model is not running to be asked.
  notRunning,

  /// The model is running but has not been asked yet.
  notChecked,

  /// The model was asked and did not answer with a tool call.
  failed,

  /// The check is busy with another model (a helper model, or chat's own
  /// when the wizard picked a different one), so this one cannot be asked.
  otherModel,
}

/// One rule for desktop and the phone relay.
WorldToolsGate worldFromWikiToolsGate(StudioToolCheck check) {
  if (check.support == ToolCallSupport.supported) return WorldToolsGate.ready;
  if (check.testing) return WorldToolsGate.checking;
  if (check.support == ToolCallSupport.unsupported) {
    return WorldToolsGate.failed;
  }
  if (!check.backendReady) return WorldToolsGate.notRunning;
  if (!check.checkable) return WorldToolsGate.otherModel;
  return WorldToolsGate.notChecked;
}

/// Plain words for each locked state; null when the wizard may run.
/// [onPhone] swaps the desktop's "Start Backend above" for the phone's path.
String? worldFromWikiToolsCopy(WorldToolsGate gate, {bool onPhone = false}) {
  switch (gate) {
    case WorldToolsGate.ready:
      return null;
    case WorldToolsGate.checking:
      return 'Checking whether this model can use tools…';
    case WorldToolsGate.notRunning:
      return 'This wizard needs a model that can use tools, and the app '
          'checks that by asking the model itself, so it has to be running '
          'first. ${onPhone ? 'Start it on the Models page' : 'Press Start Backend above'} '
          '(or connect your online provider), and the check runs by itself.';
    case WorldToolsGate.notChecked:
      return "This model hasn't been checked for tools yet. Press Check now "
          'and it takes a few seconds.';
    case WorldToolsGate.failed:
      return 'This model was tested and didn\'t answer the tool-calling check '
          'correctly, so it can\'t be used for World from Wiki. Pick a '
          'different model (for example Qwen 3 or Gemma 4) and it will be '
          'tested again.';
    case WorldToolsGate.otherModel:
      return "This model hasn't been checked for tools yet, and the app can "
          'only check the model your chats use right now. Make it your chat '
          'model (${onPhone ? 'in Settings' : 'pick it again above'}), and '
          'the check runs by itself.';
  }
}

/// Whether the locked state offers a button that asks the model again (the
/// same test as a tap on the Tool calling pill).
bool worldFromWikiToolsCanRetest(WorldToolsGate gate) =>
    gate == WorldToolsGate.notChecked;
