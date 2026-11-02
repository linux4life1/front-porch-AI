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

import 'package:front_porch_ai/services/web/facade/gen_preset_chat.dart';
import 'package:front_porch_ai/services/web/facade/gen_presets_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// Generation presets on the phone (issue 686): the Settings bar, the model
/// cards' preset pickers, the model-switch toast, and the chat drawer's
/// Generation section. Samplers are session-grade like the rest of
/// Settings' sliders: the auth middleware's session is the gate, with no
/// password step-up. Every preset write answers with the GET body.
class WebGenPresetRoutes {
  WebGenPresetRoutes(this._presets, this._chat, Router router) {
    router.get('/api/gen-presets', (shelf.Request r) => _ok());
    router.post('/api/gen-presets/save', _save);
    router.post('/api/gen-presets/load', _load);
    router.post('/api/gen-presets/delete', _delete);
    router.post('/api/gen-presets/link', _link);
    router.post('/api/gen-presets/reset-all', (shelf.Request r) async {
      await _presets.resetAll();
      return _ok();
    });
    router.post('/api/gen-presets/undo', _undo);
    router.post('/api/gen-presets/dismiss', _dismiss);
    router.get('/api/chat/generation', (shelf.Request r) => _chatOk());
    router.put('/api/chat/generation', _chatPatch);
    router.post('/api/chat/generation/preset', _chatPreset);
  }

  final GenPresetsFacade _presets;
  final GenPresetChat _chat;

  static const _maxName = 80;

  shelf.Response _ok([Map<String, Object?> extra = const {}]) =>
      JsonResponse.ok({..._presets.read(), ...extra});

  shelf.Response _chatOk() => JsonResponse.ok(_chat.read());

  static shelf.Response _noChat() => JsonResponse.error(409, 'No chat is open');

  /// The body, or null when it is not a JSON object.
  static Future<Map<String, dynamic>?> _body(shelf.Request request) async {
    try {
      return await RequestBody.readJsonMap(request);
    } on FormatException {
      return null;
    }
  }

  /// A usable preset name from [raw], or null.
  static String? _name(Object? raw) {
    if (raw is! String) return null;
    final clean = raw.trim();
    return clean.isEmpty || clean.length > _maxName ? null : clean;
  }

  /// A saved preset named in [body], or the response refusing it.
  Future<(String?, shelf.Response?)> _known(shelf.Request request) async {
    final body = await _body(request);
    if (body == null) return (null, JsonResponse.badRequest('Invalid body'));
    final name = body['name'];
    if (name is! String || !_presets.has(name)) {
      return (null, JsonResponse.error(404, 'No preset named "$name"'));
    }
    return (name, null);
  }

  Future<shelf.Response> _save(shelf.Request request) async {
    final body = await _body(request);
    if (body == null) return JsonResponse.badRequest('Invalid body');
    final name = _name(body['name']);
    if (name == null) {
      return JsonResponse.badRequest(
        'A preset needs a name of 1 to $_maxName characters',
      );
    }
    final values = body['values'];
    if (values != null && values is! Map) {
      return JsonResponse.badRequest('values must be an object');
    }
    await _presets.save(name, values);
    return _ok();
  }

  Future<shelf.Response> _load(shelf.Request request) async {
    final (name, refused) = await _known(request);
    if (refused != null) return refused;
    await _presets.load(name!);
    return _ok();
  }

  Future<shelf.Response> _delete(shelf.Request request) async {
    final (name, refused) = await _known(request);
    if (refused != null) return refused;
    await _presets.delete(name!);
    return _ok();
  }

  /// `{name: string | null, modelKey?}`: links the model (the chat model
  /// when no key is given) to the preset, or unlinks it.
  Future<shelf.Response> _link(shelf.Request request) async {
    final body = await _body(request);
    if (body == null) return JsonResponse.badRequest('Invalid body');
    final name = body['name'];
    if (name != null && (name is! String || !_presets.has(name))) {
      return JsonResponse.error(404, 'No preset named "$name"');
    }
    final key = body['modelKey'];
    if (key != null && (key is! String || key.trim().isEmpty)) {
      return JsonResponse.badRequest('modelKey must be a model key');
    }
    if (key == null && _presets.currentModelKey.isEmpty) {
      return JsonResponse.error(409, 'No chat model is chosen');
    }
    await _presets.link(name as String?, modelKey: key as String?);
    return _ok();
  }

  Future<shelf.Response> _undo(shelf.Request request) async {
    final id = (await _body(request))?['id'];
    if (id is! int) return JsonResponse.badRequest('id must be a number');
    final undone = await _presets.undo(id);
    return _ok({'undone': undone});
  }

  Future<shelf.Response> _dismiss(shelf.Request request) async {
    final id = (await _body(request))?['id'];
    if (id is! int) return JsonResponse.badRequest('id must be a number');
    _presets.dismiss(id);
    return _ok();
  }

  /// `{values: {key: value | null}}`; a null puts that value back on the
  /// global one.
  Future<shelf.Response> _chatPatch(shelf.Request request) async {
    final values = (await _body(request))?['values'];
    if (values is! Map<String, dynamic>) {
      return JsonResponse.badRequest('values must be an object');
    }
    final refused = GenPresetChat.refusal(values);
    if (refused != null) return JsonResponse.badRequest(refused);
    if (!await _chat.patch(values)) return _noChat();
    return _chatOk();
  }

  /// `{name: string | null}`: copies the preset into this chat, or clears
  /// the chat's values so it follows the model.
  Future<shelf.Response> _chatPreset(shelf.Request request) async {
    final body = await _body(request);
    if (body == null) return JsonResponse.badRequest('Invalid body');
    final name = body['name'];
    if (name != null && (name is! String || !_presets.has(name))) {
      return JsonResponse.error(404, 'No preset named "$name"');
    }
    final values = name == null ? null : _presets.valuesOf(name as String);
    if (!await _chat.loadPreset(name as String?, values)) return _noChat();
    return _chatOk();
  }
}
