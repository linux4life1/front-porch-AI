// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// When a finished night lands before they write, the body lands with the
// clock. After-reply needs must not pour a second sleep.

part of '../chat_service.dart';

extension ChatServiceNightSkip on ChatService {
  /// The clock already jumped. The after-reply needs pass is the only
  /// writer for this beat, so the body is not patched here.
  void _applyNightSkipRestore() {}
}
