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

import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// ⌘F find-in-chat on the phone: the same engine scan the desktop bar runs.
class WebChatSearchRoutes {
  WebChatSearchRoutes(this._facade, Router router) {
    router.get('/api/chat/search', _search);
  }

  final ChatFacade _facade;

  /// `?q=…&regex=1&case=1`. Awaits the server-side history backfill, so a
  /// long-chat search may take a beat — the FindBar spins meanwhile.
  Future<shelf.Response> _search(shelf.Request request) async {
    final params = request.url.queryParameters;
    return JsonResponse.ok(
      await _facade.searchTranscript(
        params['q'] ?? '',
        regex: params['regex'] == '1',
        caseSensitive: params['case'] == '1',
      ),
    );
  }
}
