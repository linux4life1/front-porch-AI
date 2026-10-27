// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Did time pass?" (#629) answered from the PWA: the send waiting on the
// question goes on with the player's pick. The question is the snapshot's
// `pendingSkip`; it leaves the snapshot once answered, closing the sheet
// (and the desktop dialog) everywhere.

import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/chat/time_skip/time_skip.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// POST /api/chat/skip-confirm — `{choice: i}` takes the i-th offered
/// skip, `{none: true}` sends with no skip, `{other: "8h"}` reads like the
/// `/skip` tag, and `{}` keeps the reader's guess. 409 when nothing is
/// asked (already answered elsewhere); 400 for a choice or text it cannot
/// read, with the question still open.
Future<shelf.Response> handleSkipConfirm(
  ChatFacade facade,
  shelf.Request request,
) async {
  final Map<String, dynamic> body;
  try {
    body = await RequestBody.readJsonMap(request);
  } catch (_) {
    return JsonResponse.badRequest('Invalid JSON body');
  }
  final chat = facade.chat;
  final question = chat.pendingSkip;
  if (question == null) {
    return JsonResponse.error(409, 'No time skip is waiting on an answer.');
  }
  final SkipVerdict? answer;
  if (body['none'] == true) {
    answer = SkipVerdict.none;
  } else if (body['other'] is String) {
    answer = SkipTag.readArgs(body['other'] as String);
    if (answer == null) return JsonResponse.badRequest(kSkipTagUsage);
  } else if (body.containsKey('choice')) {
    final i = body['choice'];
    if (i is! int || i < 0 || i >= question.choices.length) {
      return JsonResponse.badRequest('choice is out of range');
    }
    answer = question.choices[i].verdict;
  } else {
    answer = null;
  }
  chat.answerSkip(answer);
  return JsonResponse.ok({'ok': true});
}
