// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// A greeting's opening bars under the chat's stored Needs switch. The rest
/// of the greeting seed is [GreetingPicker] (doors/cast/greeting_picker.dart).
/// This part stays because test/hygiene/needs_gate_ratchet_test.dart names
/// it as a file that seeds Needs state from a greeting.
extension ChatServiceGreetingSeed on ChatService {
  /// The live vector a greeting commit seeds (1:1, or a member greet).
  void _seedGreetingNeeds(Map<String, int> baselines) {
    if (_needsSimEnabled) {
      _needsSimulation.initializeFreshWithDefaults(baselines);
    } else {
      _needsSimulation.clearVector();
    }
    _needsSimulation.resetBuffers();
  }

  /// One member's slot under a group's custom greeting.
  void _seedSlotNeeds(GroupMemberRealism slot, Map<String, int> baselines) {
    if (_needsSimEnabled) {
      slot.needs = baselines;
    }
  }
}
