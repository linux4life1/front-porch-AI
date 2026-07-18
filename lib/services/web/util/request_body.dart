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

import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart' as shelf;

/// Safe request-body parsing with a size cap, so a malicious or buggy client
/// cannot stream an unbounded body into memory on an internet-exposed server
/// (Tailscale Funnel / ngrok / port-forward).
class RequestBody {
  const RequestBody._();

  /// Default 8 MiB cap. Avatar/character imports use their own larger limit.
  static const int defaultMaxBytes = 8 * 1024 * 1024;

  /// 32 MiB cap for binary uploads (character-card PNGs, .byaf archives).
  static const int uploadMaxBytes = 32 * 1024 * 1024;

  /// Read the raw request body as bytes, throwing [BodyTooLarge] past [maxBytes].
  static Future<Uint8List> readBytes(
    shelf.Request request, {
    int maxBytes = defaultMaxBytes,
  }) async {
    final declared = request.contentLength;
    if (declared != null && declared > maxBytes) {
      throw const BodyTooLarge();
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request.read()) {
      builder.add(chunk);
      if (builder.length > maxBytes) throw const BodyTooLarge();
    }
    return builder.takeBytes();
  }

  /// Read the body as a UTF-8 string, throwing [BodyTooLarge] past [maxBytes].
  static Future<String> readString(
    shelf.Request request, {
    int maxBytes = defaultMaxBytes,
  }) async {
    return utf8.decode(
      await readBytes(request, maxBytes: maxBytes),
      allowMalformed: true,
    );
  }

  /// Read and decode a JSON object body. Returns an empty map for an empty body;
  /// throws [FormatException] for malformed JSON or a non-object top level.
  static Future<Map<String, dynamic>> readJsonMap(
    shelf.Request request, {
    int maxBytes = defaultMaxBytes,
  }) async {
    final raw = await readString(request, maxBytes: maxBytes);
    if (raw.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object body');
    }
    return decoded;
  }
}

/// Thrown when a request body exceeds the configured cap.
class BodyTooLarge implements Exception {
  const BodyTooLarge();
  @override
  String toString() => 'Request body too large';
}
