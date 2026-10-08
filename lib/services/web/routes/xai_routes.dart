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

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/util/util.dart';
import 'package:front_porch_ai/services/xai/xai.dart';

/// Phone relay for the unofficial SuperGrok sign-in. The desktop runs the
/// device-code poll; the phone shows the code and opens the approval link
/// itself. Signing in or out swaps the account generation bills to, so both
/// need the same password step-up as saving an API key. Tokens never leave
/// the desktop — status carries only the phase, email, and code.
class XaiRoutes {
  XaiRoutes(
    Router router, {
    required AuthService auth,
    required SuperGrokAuth superGrok,
  }) : _auth = auth,
       _superGrok = superGrok {
    router.get('/api/backend/xai', status);
    router.post('/api/backend/xai/sign-in', signIn);
    router.post('/api/backend/xai/cancel', cancel);
    router.post('/api/backend/xai/check', check);
    router.post('/api/backend/xai/sign-out', signOut);
  }

  final AuthService _auth;
  final SuperGrokAuth _superGrok;

  shelf.Response status(shelf.Request request) =>
      JsonResponse.ok(_superGrok.toJson());

  Future<shelf.Response> signIn(shelf.Request request) =>
      _steppedUp(request, () => _superGrok.startSignIn());

  Future<shelf.Response> signOut(shelf.Request request) =>
      _steppedUp(request, _superGrok.signOut);

  shelf.Response cancel(shelf.Request request) {
    _superGrok.cancelSignIn();
    return status(request);
  }

  Future<shelf.Response> check(shelf.Request request) async {
    await _superGrok.checkAccess();
    return status(request);
  }

  Future<shelf.Response> _steppedUp(
    shelf.Request request,
    Future<void> Function() action,
  ) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final denied = await denyUnlessSteppedUp(
      auth: _auth,
      body: body,
      request: request,
    );
    if (denied != null) return denied;
    await action();
    return status(request);
  }
}
