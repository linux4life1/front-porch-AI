import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class KoboldBinaryVersion {
  static const String fileName = '.koboldcpp_version';

  /// Reads version + size from {binDir}/.koboldcpp_version.
  /// Returns (null, null) if file missing or corrupt.
  static Future<({String? version, int? size})> read(String binDir) async {
    final file = File(p.join(binDir, fileName));
    try {
      if (!await file.exists()) return (version: null, size: null);
      final json = jsonDecode(await file.readAsString());
      return (version: json['version'] as String?, size: json['size'] as int?);
    } catch (_) {
      return (version: null, size: null);
    }
  }

  /// The version of the engine at [executablePath], when the record next to
  /// it was written for this binary (its size says so); else null. A record
  /// left from another engine would refuse a current one as too old.
  static Future<String?> versionFor(String executablePath) async {
    final rec = await read(p.dirname(executablePath));
    if (rec.version == null || rec.size == null) return null;
    try {
      final f = File(executablePath);
      if (!await f.exists() || await f.length() != rec.size) return null;
    } on FileSystemException catch (e) {
      debugPrint('[Kobold] the engine file could not be read: $e');
      return null;
    }
    return rec.version;
  }

  /// Writes version + size to {binDir}/.koboldcpp_version.
  static Future<void> write(
    String binDir, {
    required String version,
    required int size,
  }) async {
    final file = File(p.join(binDir, fileName));
    try {
      await file.writeAsString(jsonEncode({'version': version, 'size': size}));
    } catch (_) {}
  }
}
