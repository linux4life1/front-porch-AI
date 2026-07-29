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

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:front_porch_ai/services/chat/milestone_feed.dart';

part 'milestone_providers.g.dart';

/// "Our Story" timeline state (Living Time §7) — an @riverpod AsyncNotifier
/// (project standard): the async build IS the fetch, consumers render
/// through AsyncValue, and the class is unit-testable in a bare
/// ProviderContainer with a fake feed. Family args are plain named build
/// params; `revision` (message count) is bumped by the host widget so the
/// feed refetches when the chat moves. When v1.5 milestone writes land,
/// mutation methods go on this notifier — the reason it's a class, not a
/// FutureProvider.
@riverpod
class MilestoneTimeline extends _$MilestoneTimeline {
  @override
  Future<List<MilestoneEntry>> build({
    required MilestoneFeed feed,
    required String sessionId,
    required String characterId,
    required int revision,
  }) => feed.entriesFor(sessionId: sessionId, characterId: characterId);
}
