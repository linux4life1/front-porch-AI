// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// KoboldCpp's four calls for saving and loading the cache it holds: what the
// slot keeper asks of the engine, and nothing else.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/kobold_admin_swap.dart';

/// What `check_state` says: how many chats the engine can keep, how much of
/// each, and what its cache holds now.
class KoboldSlotCheck {
  const KoboldSlotCheck({
    required this.ok,
    this.slotTokens = const [],
    this.liveTokens = 0,
  });

  /// False when the engine would not answer: admin off, no model loaded,
  /// or no admin folder. KoboldCpp does not say which.
  final bool ok;

  /// Tokens saved in each slot; its length is how many slots there are.
  final List<int> slotTokens;

  /// Tokens in the cache now.
  final int liveTokens;
}

class KoboldSlotLoad {
  const KoboldSlotLoad({required this.ok, this.tokens = 0});

  /// False for an empty slot.
  final bool ok;

  /// Tokens in the cache after the call.
  final int tokens;
}

class KoboldSlotSave {
  const KoboldSlotSave({required this.ok, this.bytes = 0, this.tokens = 0});

  /// False when the engine ran out of memory for the copy.
  final bool ok;
  final int bytes;
  final int tokens;
}

/// The engine could not be asked. [busy] means it answered that it was busy
/// (HTTP 429 or 503): the call may be made again another time.
class KoboldSlotException implements Exception {
  const KoboldSlotException(
    this.message, {
    this.busy = false,
    this.timedOut = false,
  });

  final String message;
  final bool busy;

  /// No answer in time: the engine may still be doing what it was asked.
  final bool timedOut;

  @override
  String toString() => message;
}

abstract class KoboldSlotApi {
  Future<KoboldSlotCheck> check();
  Future<KoboldSlotLoad> load(int slot);
  Future<KoboldSlotSave> save(int slot);

  /// Frees every slot; KoboldCpp has no call for one.
  Future<bool> clear();
}

/// The calls over HTTP, to the engine on [baseUrl]. One try each: a slot
/// call that fails is the engine's answer, not a blip to repeat.
class KoboldHttpSlotApi implements KoboldSlotApi {
  KoboldHttpSlotApi(
    this._baseUrl, {
    Duration timeout = kKoboldAdminHttpTimeout,
    http.Client Function()? client,
  }) : _timeout = timeout,
       _client = client ?? http.Client.new;

  /// Read at each call: the service's port can change between starts.
  final String Function() _baseUrl;
  final Duration _timeout;
  final http.Client Function() _client;

  @override
  Future<KoboldSlotCheck> check() async {
    final body = await _post('check_state', const {'slot': 0});
    final old = body['old_states'];
    return KoboldSlotCheck(
      ok: koboldAdminSuccessFlag(body['success']),
      slotTokens: [
        if (old is List)
          for (final s in old) s is Map ? _int(s['tokens']) : 0,
      ],
      liveTokens: _int(body['new_tokens']),
    );
  }

  @override
  Future<KoboldSlotLoad> load(int slot) async {
    final body = await _post('load_state', {'slot': slot});
    return KoboldSlotLoad(
      ok: koboldAdminSuccessFlag(body['success']),
      tokens: _int(body['new_tokens']),
    );
  }

  @override
  Future<KoboldSlotSave> save(int slot) async {
    final body = await _post('save_state', {'slot': slot});
    return KoboldSlotSave(
      ok: koboldAdminSuccessFlag(body['success']),
      bytes: _int(body['new_state_size']),
      tokens: _int(body['new_tokens']),
    );
  }

  @override
  Future<bool> clear() async => koboldAdminSuccessFlag(
    (await _post('clear_state', const <String, Object>{}))['success'],
  );

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  Future<Map<dynamic, dynamic>> _post(
    String call,
    Map<String, Object> body,
  ) async {
    final client = _client();
    try {
      final response = await client
          .post(
            Uri.parse('${_baseUrl()}/api/admin/$call'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode == 429 || response.statusCode == 503) {
        throw KoboldSlotException(
          'KoboldCpp was busy (HTTP ${response.statusCode}).',
          busy: true,
        );
      }
      if (response.statusCode != 200) {
        throw KoboldSlotException(
          'KoboldCpp answered HTTP ${response.statusCode} to $call.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw KoboldSlotException('KoboldCpp gave no usable answer to $call.');
      }
      return decoded;
    } on KoboldSlotException {
      rethrow;
    } on TimeoutException {
      throw KoboldSlotException(
        'KoboldCpp did not answer $call in time.',
        timedOut: true,
      );
    } on FormatException catch (e) {
      throw KoboldSlotException('KoboldCpp gave a broken answer to $call: $e');
    } on Object catch (e) {
      throw KoboldSlotException('KoboldCpp could not be asked $call: $e');
    } finally {
      client.close();
    }
  }
}
