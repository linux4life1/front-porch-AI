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

import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/tool_choice_style_probe.dart';

/// OpenAI `tool_choice` value.
///
/// [functionName] non-null → `{"type":"function","function":{"name": ...}}`
/// (scalar evals, ping, chargen). Null → `'auto'` (Journal/Growth, where
/// zero calls is a valid honest empty).
Object toolChoiceValue({String? functionName}) {
  if (functionName == null || functionName.isEmpty) return 'auto';
  return {
    'type': 'function',
    'function': {'name': functionName},
  };
}

Object _styleValue(ToolChoiceStyle style, {String? functionName}) {
  switch (style) {
    case ToolChoiceStyle.named:
      return toolChoiceValue(functionName: functionName);
    case ToolChoiceStyle.required:
      return 'required';
    case ToolChoiceStyle.auto:
      return 'auto';
  }
}

/// Attach `tools` / `tool_choice` / `stream` onto [payload]. One builder so
/// the Kobold door and the OpenRouter door cannot drift.
Map<String, dynamic> attachTools(
  Map<String, dynamic> payload, {
  required List<Map<String, dynamic>> tools,
  String? toolChoice,
  bool stream = false,
  ToolChoiceStyle style = ToolChoiceStyle.named,
}) {
  payload['tools'] = tools;
  payload['tool_choice'] = _styleValue(style, functionName: toolChoice);
  payload['stream'] = stream;
  return payload;
}

final _toolChoiceBody = RegExp(r'tool[_ ]?choice', caseSensitive: false);

/// POST [basePayload] with tools attached, stepping named → required → auto
/// on a 400 whose body mentions `tool_choice`. Returns the last
/// [http.Response] — **never null**, even on an unrelated 400. The OpenRouter
/// door must still see `_isMandatoryReasoningRejection`. 429/5xx are returned
/// as-is; the door throws. Never brands XML-only.
Future<http.Response> attachToolsWithStyleRetry({
  required String identity,
  required List<Map<String, dynamic>> tools,
  String? toolChoice,
  required Map<String, dynamic> basePayload,
  required Future<http.Response> Function(Map<String, dynamic> payload) post,
  ToolChoiceStyleProbe? probe,
  bool stream = false,
}) async {
  final styleProbe = probe ?? ToolChoiceStyleProbe.instance;
  var style = styleProbe.styleFor(identity);
  // Journal/Growth (`toolChoice` null) always send `'auto'` — do not step.
  if (toolChoice == null || toolChoice.isEmpty) {
    style = ToolChoiceStyle.auto;
  }

  Future<http.Response> once(ToolChoiceStyle s) {
    final payload = Map<String, dynamic>.from(basePayload);
    attachTools(
      payload,
      tools: tools,
      toolChoice: toolChoice,
      stream: stream,
      style: s,
    );
    return post(payload);
  }

  var response = await once(style);
  if (toolChoice == null || toolChoice.isEmpty) return response;
  if (response.statusCode != 400) return response;
  if (!_toolChoiceBody.hasMatch(response.body)) return response;

  if (style == ToolChoiceStyle.named) {
    styleProbe.remember(identity, ToolChoiceStyle.required);
    response = await once(ToolChoiceStyle.required);
    if (response.statusCode != 400) return response;
    if (!_toolChoiceBody.hasMatch(response.body)) return response;
    style = ToolChoiceStyle.required;
  }
  if (style == ToolChoiceStyle.required) {
    styleProbe.remember(identity, ToolChoiceStyle.auto);
    return once(ToolChoiceStyle.auto);
  }
  return response;
}
