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

  /// The first KoboldCpp that splits the batch in two: the logical batch
  /// (`batchsize`) and the physical one (`ubatchsize`), the tokens computed
  /// at once, which sets the working memory. An older engine reads
  /// `batchsize` as the physical batch and ignores `ubatchsize`.
  static const String splitBatchFrom = '1.122';

  /// Whether an engine of [version] reads `ubatchsize`. An unknown version
  /// does not: the single field means the same on every engine.
  static bool splitsBatch(String? version) {
    final have = _numbers(version);
    if (have == null) return false;
    final need = _numbers(splitBatchFrom)!;
    for (var i = 0; i < need.length; i++) {
      if (have[i] != need[i]) return have[i] > need[i];
    }
    return true;
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

  /// Every build recorded in [binDir]. Linux keeps more than one build side
  /// by side (the ROCm build beside the Vulkan one), each with its own
  /// version, so the record holds one entry per build, told apart by size.
  /// A record written by an older app is a single entry.
  static Future<List<({String version, int size})>> _builds(
    String binDir,
  ) async {
    final file = File(p.join(binDir, fileName));
    try {
      if (!await file.exists()) return const [];
      final json = jsonDecode(await file.readAsString());
      final list = json['builds'] is List ? json['builds'] as List : [json];
      return [
        for (final b in list)
          if (b is Map && b['version'] is String && b['size'] is int)
            (version: b['version'] as String, size: b['size'] as int),
      ];
    } catch (e) {
      debugPrint('[Kobold] the engine version record could not be read: $e');
      return const [];
    }
  }

  /// The version of the engine at [executablePath], when the record next to
  /// it was written for this binary (its size says so); else null. A record
  /// left from another engine would refuse a current one as too old.
  static Future<String?> versionFor(String executablePath) async {
    final builds = await _builds(p.dirname(executablePath));
    if (builds.isEmpty) return null;
    final int length;
    try {
      final f = File(executablePath);
      if (!await f.exists()) return null;
      length = await f.length();
    } on FileSystemException catch (e) {
      debugPrint('[Kobold] the engine file could not be read: $e');
      return null;
    }
    for (final b in builds.reversed) {
      if (b.size == length) return b.version;
    }
    return null;
  }

  /// Records [version] for the build of [size] bytes in
  /// {binDir}/.koboldcpp_version, keeping the other builds' entries. The
  /// top-level fields name the newest write, as older apps read them.
  static Future<void> write(
    String binDir, {
    required String version,
    required int size,
  }) async {
    final file = File(p.join(binDir, fileName));
    final builds = [
      for (final b in await _builds(binDir))
        if (b.size != size) {'version': b.version, 'size': b.size},
      {'version': version, 'size': size},
    ];
    try {
      await file.writeAsString(
        jsonEncode({'version': version, 'size': size, 'builds': builds}),
      );
    } catch (e) {
      debugPrint('[Kobold] the engine version record was not written: $e');
    }
  }
}
