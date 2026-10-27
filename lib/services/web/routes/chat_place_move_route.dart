// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 6: answering a suggested scene move over the relay. Its own file
// because chat_routes.dart sits one line under the 500-line ratchet and
// every slice-4/6 endpoint has to fit somewhere.

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

import 'chat_skip_confirm_route.dart';

/// POST /api/chat/place-move — {accept: true} runs the desktop's manual
/// swap through the ONE slots writer; {accept: false} records the
/// decline for this Setting. The flag then leaves the snapshot on the
/// next tick, closing the modal in both shells.
/// POST /api/chat/place-mint — answer a proposed new place:
/// {action: 'add_move' | 'add' | 'ignore'}. Minting runs the same
/// PlaceFactory the desktop dialog taps into; 'ignore' remembers the
/// name for this chat. A bad draft answers with its honest error —
/// the PWA shows it and the flag is already cleared (no nag loop).
Future<shelf.Response> handlePlaceMint(
  ChatFacade facade,
  shelf.Request request,
) async {
  final Map<String, dynamic> body;
  try {
    body = await RequestBody.readJsonMap(request);
  } catch (_) {
    return JsonResponse.badRequest('Invalid JSON body');
  }
  final action = body['action']?.toString() ?? 'ignore';
  if (action == 'ignore') {
    facade.chat.ignoreMintedPlace();
    return JsonResponse.ok({'ok': true});
  }
  final result = await facade.chat.acceptMintedPlace(
    alsoMove: action == 'add_move',
  );
  return JsonResponse.ok({
    'ok': result.ok,
    if (result.error != null) 'error': result.error,
  });
}

/// The three scene-suggestion endpoints, registered as a set so the
/// big chat router carries one line for the whole family.
void registerSceneLocationRoutes(
  Router router,
  ChatFacade facade, {
  void Function(shelf.Request)? dismissGuestPicker,
}) {
  router.post('/api/chat/place-move', (r) => handlePlaceMove(facade, r));
  router.post('/api/chat/place-mint', (r) => handlePlaceMint(facade, r));
  router.post('/api/chat/skip-confirm', (r) => handleSkipConfirm(facade, r));
}

/// POST /api/chat/guest-picker/dismiss — close a parked `/join` picker.
/// (Same extraction rationale as [handlePlaceMove]; kept beside it so the
/// two scene-prompt endpoints live in one readable place.)
shelf.Response handleDismissGuestPicker(ChatFacade facade) {
  facade.dismissGuestPicker();
  return JsonResponse.ok({'ok': true});
}

Future<shelf.Response> handlePlaceMove(
  ChatFacade facade,
  shelf.Request request,
) async {
  final Map<String, dynamic> body;
  try {
    body = await RequestBody.readJsonMap(request);
  } catch (_) {
    return JsonResponse.badRequest('Invalid JSON body');
  }
  await facade.answerPlaceMove(body['accept'] == true);
  return JsonResponse.ok({'ok': true});
}
