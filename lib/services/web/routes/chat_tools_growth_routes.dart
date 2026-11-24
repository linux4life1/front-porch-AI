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

import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// Growth POST actions the sidebar may send: the ring actions plus the
/// kit-settle trio (docs/design/boons-and-bogies.md §4, ruling 13). A name
/// the facade switches on but this set forgot 400s the request before it
/// ever reaches Dart logic — the phase-2 `undoBb` lesson, kept as a comment
/// so the next action added to the switch lands here too.
const knownGrowthActions = {
  'plant',
  'edit',
  'pin',
  'retire',
  'restore',
  'delete',
  'reset',
  'check',
  'undoBb',
  'acceptKit',
  'declineKit',
  'kitAgain',
  'milestoneAnswer',
  'milestoneReplay',
  'milestoneDismiss',
};

/// `POST /api/chat/tools/growth` — one growth mutation, then the fresh
/// growth block so the timeline reflects the new state. Split out of
/// chat_tools_routes.dart, which was at the 500-line bar.
Future<shelf.Response> handleGrowthPost({
  required shelf.Request request,
  required Future<Map<String, dynamic>> Function(shelf.Request) readJson,
  required ChatToolsFacade facade,
}) async {
  final body = await readJson(request);
  final action = body['action']?.toString() ?? '';
  final participant =
      body['participant']?.toString() ??
      request.url.queryParameters['participant'];
  if (!knownGrowthActions.contains(action)) {
    return JsonResponse.badRequest('Unknown growth action: $action');
  }
  await facade.growthAction(participant, action, body);
  return JsonResponse.ok({
    ...facade.growth(participant),
    // A milestone answer says what it did: the card stays up, with a
    // reason, when a new bogey would pass the cap.
    if (action == 'milestoneAnswer')
      'milestoneOutcome': facade.lastMilestoneOutcome,
  });
}

/// `GET /api/chat/tools/growth/moments` — the focused owner's Moments
/// (`?participant=`), newest first, with the revision they were read at.
Future<shelf.Response> handleMomentsGet({
  required shelf.Request request,
  required ChatToolsFacade facade,
}) async => JsonResponse.ok(
  await facade.moments(request.url.queryParameters['participant']),
);
