import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class KoboldBinaryVersion {
  static const String fileName = '.koboldcpp_version';

  /// The oldest KoboldCpp the app runs. An older one stops at load on the
  /// config the app stages: it reads the cache type as a number, and a
  /// config file is not converted the way a command line is. There is no
  /// older form of the config to write for it, so it is refused.
  static const String minimum = '1.112';

  /// Why an engine of [version] is too old, in words the user can act on,
  /// or null when it is not. An engine whose version is not known (no
  /// record yet, or text with no number in it) counts as current: the app
  /// downloads the engine itself.
  static String? tooOldProblem(String? version) {
    final have = _numbers(version);
    if (have == null) return null;
    final need = _numbers(minimum)!;
    for (var i = 0; i < need.length; i++) {
      if (have[i] != need[i]) {
        return have[i] > need[i]
            ? null
            : 'This KoboldCpp ($version) is too old for the app. Update '
                  'KoboldCpp to $minimum or newer, then start it again.';
      }
    }
    return null;
  }

  /// Major, minor and patch of the first version number in [version].
  static List<int>? _numbers(String? version) {
    final found = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(version ?? '');
    if (found == null) return null;
    return [for (var i = 1; i <= 3; i++) int.parse(found.group(i) ?? '0')];
  }

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
