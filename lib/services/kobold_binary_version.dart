import 'dart:convert';
import 'dart:io';
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
      return (
        version: json['version'] as String?,
        size: json['size'] as int?,
      );
    } catch (_) {
      return (version: null, size: null);
    }
  }

  /// Writes version + size to {binDir}/.koboldcpp_version.
  static Future<void> write(
    String binDir, {
    required String version,
    required int size,
  }) async {
    final file = File(p.join(binDir, fileName));
    try {
      await file.writeAsString(
        jsonEncode({'version': version, 'size': size}),
      );
    } catch (_) {}
  }
}
