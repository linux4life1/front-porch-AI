// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Bridge: the Action Suggestions names ChatService consumers have always
// called, each a one-line call on [ChatService.actionsDoor]. The shell
// exports this library, so callers keep their imports.

import 'package:front_porch_ai/services/chat_service.dart';

/// Action Suggestions — clear + LLM-generated quick-reply actions.
extension ChatServiceActions on ChatService {
  void clearSuggestions() => actionsDoor.clearSuggestions();
  Future<void> generateActions() => actionsDoor.generateActions();
}
