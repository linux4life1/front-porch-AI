// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/backporch/api/backporch_api_types.dart';

/// JSON-over-HTTP calls to the Stoop server at [baseUrl]: bearer auth, a 30 s
/// timeout, and non-2xx bodies turned into [BackporchApiException].
class BackporchTransport {
  BackporchTransport(this.baseUrl);

  final String baseUrl;

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final client = http.Client();
    try {
      final res = await client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return parse(res);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> get(String path, String token) async {
    final client = http.Client();
    try {
      final res = await client
          .get(
            Uri.parse('$baseUrl$path'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      return parse(res);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final client = http.Client();
    try {
      final res = await client
          .patch(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      return parse(res);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> delete(String path, String token) async {
    final client = http.Client();
    try {
      final res = await client
          .delete(
            Uri.parse('$baseUrl$path'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      return parse(res);
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> parse(http.Response res) {
    Map<String, dynamic> json = <String, dynamic>{};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {
        // Non-JSON body (e.g. a proxy error page) — fall through to status code.
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    throw BackporchApiException(
      res.statusCode,
      (json['error'] as String?) ?? 'http_${res.statusCode}',
      (json['detail'] as String?)?.trim().isNotEmpty == true
          ? (json['detail'] as String).trim()
          : null,
    );
  }
}
