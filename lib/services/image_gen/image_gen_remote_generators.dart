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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/image/image.dart';

/// Detect if URL is an OpenRouter-style API (uses chat/completions for images).
bool isOpenRouterStyle(String url) {
  return url.contains('openrouter.ai');
}

/// Remote image POST only — not catalog (15s) or URL download (30s).
/// Ceiling is [kRemoteImageHttpTimeout] (600s), same as A1111 model load.
Future<http.Response> _postRemoteImage(
  http.Client client, {
  required Uri uri,
  required Map<String, String> headers,
  required String body,
}) async {
  try {
    return await client
        .post(uri, headers: headers, body: body)
        .timeout(kRemoteImageHttpTimeout);
  } on TimeoutException {
    throw Exception(formatRemoteImageTimeoutMessage());
  }
}

/// Generate via OpenAI-compatible /images/generations endpoint.
/// Works with Nano-GPT, direct OpenAI, and local A1111/SD servers.
///
/// NOTE: [negativePrompt] is accepted for signature symmetry but is NOT
/// sent — the OpenAI images API has no negative_prompt parameter and
/// rejects unknown fields, so it is deliberately dropped here (and by
/// [generateViaOpenRouter]). Negatives only take effect on the A1111 and
/// Draw Things backends.
Future<Uint8List> generateViaOpenAICompat({
  required String apiUrl,
  required String apiKey,
  required String model,
  required String prompt,
  String negativePrompt = '',
  String size = '1024x1024',
  // When set, this is an EDIT: POST the reference (as a base64 data URI) +
  // instruction to the OpenAI-compatible /images/edits endpoint instead of
  // /images/generations. Verified against Nano-GPT (JSON imageDataUrl variant).
  Uint8List? editImage,
}) async {
  final isEdit = editImage != null;
  final imageEndpoint = isEdit
      ? '$apiUrl/images/edits'
      : '$apiUrl/images/generations';
  debugPrint('ImageGen: POST $imageEndpoint (model=$model, edit=$isEdit)');
  final uri = Uri.parse(imageEndpoint);
  final payload = isEdit
      ? <String, dynamic>{
          'model': model,
          'prompt': prompt,
          'imageDataUrl': 'data:image/png;base64,${base64Encode(editImage)}',
        }
      : <String, dynamic>{
          'model': model,
          'prompt': prompt,
          'n': 1,
          'size': size,
          'response_format': 'b64_json',
        };

  return _postImagesApi(
    uri: uri,
    apiKey: apiKey,
    payload: payload,
    endpoint: imageEndpoint,
  );
}

/// POSTs an OpenAI-shaped images request and reads `data[0]` as base64 or a
/// URL to download. Nano-GPT and xAI both answer in this shape.
Future<Uint8List> _postImagesApi({
  required Uri uri,
  required String apiKey,
  required Map<String, dynamic> payload,
  required String endpoint,
}) async {
  final client = http.Client();
  try {
    final response = await _postRemoteImage(
      client,
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      debugPrint('ImageGen: HTTP ${response.statusCode} from $endpoint');
      debugPrint('ImageGen: Response body: ${response.body}');
      String errorMsg = 'HTTP ${response.statusCode}';
      try {
        final errBody = jsonDecode(response.body);
        final error = errBody['error'];
        // Handle both OpenAI format {"error":{"message":"..."}} and Nano-GPT
        // format {"error":"Insufficient balance","message":"Available X,
        // required Y","code":"insufficient_balance"} — prefer the detailed
        // top-level message so e.g. a low-balance edit says exactly how much.
        if (error is Map<String, dynamic>) {
          errorMsg = error['message'] as String? ?? errorMsg;
        } else if (error is String) {
          final detail = errBody['message'];
          errorMsg = (detail is String && detail.isNotEmpty) ? detail : error;
        }
      } catch (_) {}
      throw Exception(errorMsg);
    }

    final body = jsonDecode(response.body);
    final data = body['data'] as List<dynamic>;
    if (data.isEmpty) throw Exception('No image data returned');

    // Handle both b64_json and url response formats
    final first = data[0] as Map<String, dynamic>;
    if (first.containsKey('b64_json')) {
      return base64Decode(first['b64_json'] as String);
    } else if (first.containsKey('url')) {
      // Download the image from the URL
      final imgResponse = await client
          .get(Uri.parse(first['url'] as String))
          .timeout(const Duration(seconds: 30));
      if (imgResponse.statusCode != 200) {
        throw Exception('Failed to download image from URL');
      }
      return imgResponse.bodyBytes;
    } else {
      throw Exception('Unexpected response format');
    }
  } finally {
    client.close();
  }
}

/// Generate via xAI's Grok Imagine. A create sends an aspect ratio and a
/// resolution instead of pixels; an edit sends the picture as an `image`
/// object to `/images/edits`.
Future<Uint8List> generateViaXai({
  required String apiUrl,
  required String apiKey,
  required String model,
  required String prompt,
  required String aspectRatio,
  required String resolution,
  Uint8List? editImage,
}) {
  final isEdit = editImage != null;
  final endpoint = isEdit
      ? '$apiUrl/images/edits'
      : '$apiUrl/images/generations';
  debugPrint('ImageGen: POST $endpoint (model=$model, edit=$isEdit)');
  return _postImagesApi(
    uri: Uri.parse(endpoint),
    apiKey: apiKey,
    endpoint: endpoint,
    payload: xaiImagePayload(
      model: model,
      prompt: prompt,
      aspectRatio: aspectRatio,
      resolution: resolution,
      editImage: isEdit
          ? 'data:image/png;base64,${base64Encode(editImage)}'
          : null,
    ),
  );
}

/// Generate via OpenRouter's chat/completions endpoint with image modality.
///
/// When [editImage] is set this is an EDIT: the reference rides as an
/// `image_url` content part (base64 data URI) alongside the instruction — the
/// only image-edit shape OpenRouter exposes (it has no /images/edits). Wired
/// from OpenRouter's documented multimodal image support but NOT verified
/// in-house (only Nano-GPT's /images/edits was); community-verified.
Future<Uint8List> generateViaOpenRouter({
  required String apiUrl,
  required String apiKey,
  required String model,
  required String prompt,
  String size = '1024x1024',
  Uint8List? editImage,
}) async {
  final uri = Uri.parse('$apiUrl/chat/completions');
  final content = editImage == null
      ? prompt
      : [
          {'type': 'text', 'text': prompt},
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/png;base64,${base64Encode(editImage)}',
            },
          },
        ];
  final payload = <String, dynamic>{
    'model': model,
    'messages': [
      {'role': 'user', 'content': content},
    ],
    'modalities': ['image'],
    'max_tokens': 4096,
  };

  final client = http.Client();
  try {
    final response = await _postRemoteImage(
      client,
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
        'HTTP-Referer': 'https://github.com/linux4life1/front-porch-AI',
        'X-Title': 'Front Porch AI',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      String errorMsg = 'HTTP ${response.statusCode}';
      try {
        final errBody = jsonDecode(response.body);
        final error = errBody['error'];
        if (error is Map<String, dynamic>) {
          errorMsg = error['message'] as String? ?? errorMsg;
        } else if (error is String) {
          errorMsg = error;
        }
      } catch (_) {}
      throw Exception(errorMsg);
    }

    final body = jsonDecode(response.body);
    final choices = body['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) throw Exception('No response choices');

    final message = choices[0]['message'] as Map<String, dynamic>;

    // OpenRouter returns the generated/edited image in message.images:
    // [{type:'image_url', image_url:{url:'data:...'|'https://...'}}] — VERIFIED
    // live against a real edit (2026-07). This is where the image actually is;
    // the `content` shapes below are legacy/other-provider fallbacks.
    final images = message['images'];
    if (images is List) {
      for (final im in images) {
        if (im is! Map<String, dynamic>) continue;
        final iu = im['image_url'];
        final url = iu is Map<String, dynamic> ? iu['url'] as String? : null;
        if (url != null) return await _imageBytesFromUrl(client, url);
      }
    }

    final content = message['content'];
    // Fallback: content as a list with image_url parts.
    if (content is List) {
      for (final part in content) {
        if (part is! Map<String, dynamic> || part['type'] != 'image_url') {
          continue;
        }
        final iu = part['image_url'];
        final url = iu is Map<String, dynamic> ? iu['url'] as String? : null;
        if (url != null) return await _imageBytesFromUrl(client, url);
      }
    }

    // Fallback: a bare base64 string in content.
    if (content is String && content.isNotEmpty) {
      try {
        return base64Decode(content);
      } catch (_) {
        throw Exception('Could not extract image from response');
      }
    }

    throw Exception('No image found in response');
  } finally {
    client.close();
  }
}

/// Decode an image reference from a chat image part — a `data:` base64 URI, or
/// an https URL to download. Shared by the OpenRouter images/content parsing.
Future<Uint8List> _imageBytesFromUrl(http.Client client, String url) async {
  if (url.startsWith('data:')) return base64Decode(url.split(',').last);
  final r = await client
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 30));
  return r.bodyBytes;
}
