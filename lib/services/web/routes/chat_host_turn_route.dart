// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group "Next" from the PWA composer. The desktop button calls
// `ChatService.triggerNextCharacter` (the rotator's stored suggestion or a
// turn-order queue pop). The web used to fake it with `/speak <name>`,
// which pre-empts the stored order and can name yesterday's speaker — this
// endpoint is the honest path. Busy/empty guards live in the service, so a
// tap that races a running turn no-ops exactly like the desktop's.

import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// POST /api/chat/host-turn — advances the group's turn on the desktop's
/// path. 409 when the open chat is not a group (nothing to advance);
/// otherwise fires and returns — the reply streams over /api/ws.
shelf.Response handleHostTurn(ChatFacade facade, shelf.Request request) {
  final chat = facade.chat;
  if (!chat.isGroupMode) {
    return JsonResponse.error(
      409,
      'This chat is not a group, so there is no turn to advance.',
    );
  }
  chat.triggerNextCharacter();
  return JsonResponse.ok({'status': 'ok'});
}
