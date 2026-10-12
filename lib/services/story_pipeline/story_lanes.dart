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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// Routes story jobs to the model each lane asks for: the worker model, or
/// a host the story picked itself (any provider, any model).
class StoryLanes {
  const StoryLanes({
    required this.worker,
    required this.hold,
    required this.host,
  });

  /// The live worker service, or null when none is configured.
  final LLMService? Function() worker;

  /// Runs [work] while holding the worker lane (so a shared GPU can swap).
  final Future<T> Function<T>(Future<T> Function() work) hold;

  /// The host for a lane's own choice, or null when it cannot be built.
  final LaneHost? Function(StoryLaneChoice choice) host;
}
