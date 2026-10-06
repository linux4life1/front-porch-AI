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

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/porch/porch.dart';
import 'package:front_porch_ai/services/web/facade/porch_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// Web twin of the desktop library's Export (multi-select) and Import
/// `.porch` / `.porchpack`. Its own `/api/porch/` prefix, so the character
/// routes' `/api/characters/<id>` can never catch these.
class WebPorchRoutes {
  WebPorchRoutes(this._facade, Router router) {
    router.post('/api/porch/export', _export);
    router.post('/api/porch/import', _import);
  }

  final PorchFacade _facade;

  /// Body `{ "ids": [...] }` → the file to save. `X-Porch-Count` says how
  /// many characters went in, `X-Porch-Groups-Left-Out` how many selected
  /// groups were not (the phone words both as the desktop does).
  Future<shelf.Response> _export(shelf.Request request) async {
    final List<String> ids;
    try {
      final body = await RequestBody.readJsonMap(request);
      ids = [for (final id in body['ids'] as List? ?? const []) id.toString()];
    } catch (_) {
      return JsonResponse.badRequest('Send the ids of the characters.');
    }
    try {
      final out = await _facade.export(ids);
      return shelf.Response.ok(
        out.bytes,
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Disposition':
              "attachment; filename*=UTF-8''${Uri.encodeComponent(out.fileName)}",
          'Cache-Control': 'no-store',
          'X-Porch-Count': '${out.count}',
          'X-Porch-Groups-Left-Out': '${out.groupsLeftOut}',
        },
      );
    } on PorchRefused catch (e) {
      return JsonResponse.error(409, e.message);
    } catch (e) {
      debugPrint('[porch] web export failed: $e');
      return JsonResponse.error(
        500,
        'The export didn’t finish. Try again; if it keeps failing, export '
        'fewer characters at a time.',
      );
    }
  }

  /// Raw file body; the name rides as `?filename=`.
  Future<shelf.Response> _import(shelf.Request request) async {
    final name = request.url.queryParameters['filename'] ?? 'characters.porch';
    final List<int> bytes;
    try {
      bytes = await RequestBody.readBytes(
        request,
        maxBytes: RequestBody.packageMaxBytes,
      );
    } on BodyTooLarge {
      return JsonResponse.error(
        413,
        'That file is too large to send from here (the limit is 256 MB). '
        'Import it on the desktop instead.',
      );
    }
    if (bytes.isEmpty) {
      return JsonResponse.badRequest('That file is empty. Pick another one.');
    }
    try {
      final report = await _facade.import(
        name,
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      );
      return JsonResponse.ok(report.toJson());
    } on PorchRefused catch (e) {
      return JsonResponse.error(409, e.message);
    } catch (e) {
      debugPrint('[porch] web import failed: $e');
      return JsonResponse.error(
        500,
        'The import didn’t finish. Try again; if it keeps failing, import it '
        'on the desktop.',
      );
    }
  }
}
