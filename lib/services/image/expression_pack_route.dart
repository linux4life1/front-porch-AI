// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/services/web/middleware/auth_middleware.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';

/// SessionStore.validate returns this for the single local web account.
const String kStudioWebAccountId = 'local';

/// Pack labels and QC verdicts. Each filename is the emotion plus `.png`.
/// Import has not stamped a disk path yet, so these are not files on disk.
/// Image bytes stay on the desktop.
Map<String, Object?> expressionPackView({
  required bool running,
  required List<ExpressionSlot> slots,
}) {
  return {
    'running': running,
    'filenames': [
      for (final slot in slots)
        if (slot.state == ExpressionSlotState.done) '${slot.emotion}.png',
    ],
    'verdicts': [
      for (final slot in slots)
        if (slot.qc != null)
          {
            'emotion': slot.emotion,
            'samePerson': slot.qc!.samePerson,
            'expressionMatches': slot.qc!.expressionMatches,
            'note': slot.qc!.note,
          },
    ],
  };
}

/// The one desktop-started pack the phone is allowed to read.
class ExpressionPackBoard {
  String? _accountId;
  List<ExpressionSlot>? _slots;
  bool _running = false;
  void Function()? _cancel;

  void publish({
    required String accountId,
    required bool running,
    required List<ExpressionSlot> slots,
    required void Function() onCancel,
  }) {
    _accountId = accountId;
    _slots = slots;
    _running = running;
    _cancel = onCancel;
  }

  Map<String, Object?>? read(String accountId) {
    final slots = _slots;
    if (slots == null || _accountId != accountId) {
      return null;
    }
    return expressionPackView(running: _running, slots: slots);
  }

  bool cancel(String accountId) {
    if (_slots == null || _accountId != accountId) {
      return false;
    }
    _cancel?.call();
    return true;
  }

  void clear() {
    _accountId = null;
    _slots = null;
    _running = false;
    _cancel = null;
  }
}

final ExpressionPackBoard expressionPackBoard = ExpressionPackBoard();

void registerExpressionPackRoutes(Router router) {
  router.get('/api/image/expression-pack', expressionPackStatus);
  router.post('/api/image/expression-pack/cancel', expressionPackCancel);
}

String? _packAccount(shelf.Request request) {
  final id = request.context[kAuthUserIdContextKey]?.toString().trim() ?? '';
  if (id.isEmpty) return null;
  return id;
}

shelf.Response expressionPackStatus(shelf.Request request) {
  final account = _packAccount(request);
  if (account == null) {
    return JsonResponse.unauthorized('Authentication required');
  }
  final body = expressionPackBoard.read(account);
  if (body == null) {
    return JsonResponse.error(404, 'No expression pack');
  }
  return JsonResponse.ok(body);
}

shelf.Response expressionPackCancel(shelf.Request request) {
  final account = _packAccount(request);
  if (account == null) {
    return JsonResponse.unauthorized('Authentication required');
  }
  if (!expressionPackBoard.cancel(account)) {
    return JsonResponse.error(404, 'No expression pack');
  }
  return JsonResponse.ok({'cancelled': true});
}
