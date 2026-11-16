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

import 'package:front_porch_ai/services/web/facade/character_authoring_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';

/// Portrait and expression authoring the web never had: attach a portrait
/// (the desktop Review step's Upload source, and the Avatar Gallery's missing
/// Set/Replace), re-tag an expression image, and import an emotion-named ZIP
/// sprite pack. Every verb mirrors a desktop method on
/// [CharacterAuthoringFacade]; nothing is reimplemented here.
class WebCharacterAvatarRoutes {
  WebCharacterAvatarRoutes(this._authoring, Router router) {
    router.post('/api/characters/<id>/portrait', _portrait);
    router.post('/api/characters/<id>/avatars/<avatarId>/label', _label);
    router.post('/api/characters/<id>/expressions/import-zip', _importZip);
  }

  final CharacterAuthoringFacade _authoring;

  /// Raw bytes; the client crops before uploading (the desktop crops in
  /// `ImageCropDialog`, the web in `ImageCropModal` — the 8b precedent).
  Future<shelf.Response> _portrait(shelf.Request request, String id) async {
    final List<int> bytes;
    try {
      bytes = await RequestBody.readBytes(
        request,
        maxBytes: RequestBody.uploadMaxBytes,
      );
    } catch (_) {
      return JsonResponse.error(413, 'File too large');
    }
    if (bytes.isEmpty) return JsonResponse.badRequest('Empty upload');
    final ok = await _authoring.attachPortrait(id, bytes);
    if (!ok) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok({'ok': true});
  }

  /// `{ "label": "<EmotionLabels value or empty>" }`; an unknown label is a
  /// 400, a missing card or avatar a 404.
  Future<shelf.Response> _label(
    shelf.Request request,
    String id,
    String avatarId,
  ) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Expected a JSON object body');
    }
    final label = (body['label']?.toString() ?? '').trim();
    if (label.isNotEmpty && !EmotionLabels.all.contains(label)) {
      return JsonResponse.badRequest('Unknown emotion label');
    }
    final ok = await _authoring.setAvatarLabel(id, avatarId, label);
    if (!ok) return JsonResponse.error(404, 'Avatar not found');
    return JsonResponse.ok({'avatars': await _authoring.avatars(id)});
  }

  /// Raw ZIP bytes. Each image file whose base name matches an emotion label
  /// becomes an expression avatar; the desktop's enable flip rides along.
  Future<shelf.Response> _importZip(shelf.Request request, String id) async {
    final List<int> bytes;
    try {
      bytes = await RequestBody.readBytes(
        request,
        maxBytes: RequestBody.uploadMaxBytes,
      );
    } catch (_) {
      return JsonResponse.error(413, 'File too large');
    }
    if (bytes.isEmpty) return JsonResponse.badRequest('Empty upload');
    final result = await _authoring.importExpressionZip(id, bytes);
    if (result == null) {
      return JsonResponse.error(404, 'Character not found');
    }
    if (result.tooLarge) {
      return JsonResponse.error(413, 'That ZIP unpacks to too much');
    }
    return JsonResponse.ok({
      'added': result.added,
      'unrecognized': result.unrecognized,
      'avatars': await _authoring.avatars(id),
    });
  }
}
