// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What Front Porch wrote to a loader and when. The loader's own modified time
/// is not trusted for this (a clock that is off, a network share, a `touch`),
/// so what was written, and when this app's clock said so, is remembered.
class City96Record {
  const City96Record({required this.hash, required this.at});

  /// SHA-256 of the text written, as hex.
  final String hash;
  final DateTime at;
}

String city96Hash(String text) => sha256.convert(utf8.encode(text)).toString();

abstract class City96Records {
  Future<City96Record?> get(String loaderPath);
  Future<void> put(String loaderPath, City96Record record);
  Future<void> remove(String loaderPath);
}

/// Kept for this run only.
class MemoryCity96Records implements City96Records {
  final Map<String, City96Record> _rows = {};

  @override
  Future<City96Record?> get(String loaderPath) async => _rows[loaderPath];

  @override
  Future<void> put(String loaderPath, City96Record record) async =>
      _rows[loaderPath] = record;

  @override
  Future<void> remove(String loaderPath) async => _rows.remove(loaderPath);
}

/// Kept across runs, so an update made before the app was restarted is still
/// known to have been made when it was.
class PrefsCity96Records implements City96Records {
  static const String key = 'city96_loader_records';

  Future<Map<String, dynamic>> _read(SharedPreferences prefs) async {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : {};
    } on FormatException {
      return {};
    }
  }

  @override
  Future<City96Record?> get(String loaderPath) async {
    final row = (await _read(
      await SharedPreferences.getInstance(),
    ))[loaderPath];
    if (row is! Map) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(
      (row['at'] as num?)?.toInt() ?? 0,
    );
    final hash = row['hash']?.toString() ?? '';
    return hash.isEmpty ? null : City96Record(hash: hash, at: at);
  }

  @override
  Future<void> put(String loaderPath, City96Record record) async {
    final prefs = await SharedPreferences.getInstance();
    final rows = await _read(prefs);
    rows[loaderPath] = {
      'hash': record.hash,
      'at': record.at.millisecondsSinceEpoch,
    };
    await prefs.setString(key, jsonEncode(rows));
  }

  @override
  Future<void> remove(String loaderPath) async {
    final prefs = await SharedPreferences.getInstance();
    final rows = await _read(prefs);
    if (rows.remove(loaderPath) == null) return;
    await prefs.setString(key, jsonEncode(rows));
  }
}
