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
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/tts_voice_info.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts/sherpa_piper_engine.dart';

/// Metadata for a single Piper voice from the catalog.
class PiperVoice {
  final String key;
  final String name;
  final String languageCode;
  final String languageEnglish;
  final String countryEnglish;
  final String quality;
  final int numSpeakers;
  final Map<String, PiperVoiceFile> files;

  PiperVoice({
    required this.key,
    required this.name,
    required this.languageCode,
    required this.languageEnglish,
    required this.countryEnglish,
    required this.quality,
    required this.numSpeakers,
    required this.files,
  });

  /// Inferred gender label: 'Male', 'Female', or 'Unknown'.
  String get gender {
    final n = name.toLowerCase();
    // Check explicit markers in the name
    if (n.contains('female') || n.contains('_f')) return 'Female';
    if (n.contains('male') || n.contains('_m')) return 'Male';
    // Curated map based on Piper voice documentation / dataset origins
    return _knownGender[n] ?? 'Unknown';
  }

  /// Known gender for Piper voices (from dataset documentation).
  static const _knownGender = <String, String>{
    // English
    'alan': 'Male', 'alba': 'Female', 'amy': 'Female', 'aru': 'Male',
    'bryce': 'Male', 'cori': 'Female', 'danny': 'Male',
    'jenny_dioco': 'Female', 'joe': 'Male', 'john': 'Male',
    'kathleen': 'Female', 'kristin': 'Female', 'kusal': 'Male',
    'lessac': 'Female', 'ljspeech': 'Female', 'norman': 'Male',
    'ryan': 'Male', 'sam': 'Male',
    // German
    'thorsten': 'Male', 'thorsten_emotional': 'Male', 'eva_k': 'Female',
    'kerstin': 'Female', 'karlsson': 'Male', 'pavoque': 'Male',
    'ramona': 'Female',
    // French
    'gilles': 'Male', 'siwis': 'Female', 'nathalie': 'Female',
    'tom': 'Male', 'jessica': 'Female', 'upmc': 'Male',
    // Spanish
    'carlfm': 'Male', 'davefx': 'Male', 'paola': 'Female',
    // Italian
    'riccardo': 'Male', 'lisa': 'Female',
    // Portuguese
    'faber': 'Male', 'cadu': 'Male',
    // Russian
    'ruslan': 'Male', 'irina': 'Female', 'dmitri': 'Male',
    // Arabic
    'kareem': 'Male',
    // Others
    'anna': 'Female', 'berta': 'Female', 'claude': 'Male',
    'daniela': 'Female', 'darkman': 'Male', 'denis': 'Male',
    'gosia': 'Female', 'harri': 'Male', 'imre': 'Male',
    'jeff': 'Male', 'jirka': 'Male', 'lada': 'Female',
    'lili': 'Female', 'maya': 'Female', 'mihai': 'Male',
    'natia': 'Female', 'pim': 'Male', 'raya': 'Female',
    'ronnie': 'Male', 'salka': 'Female', 'steinn': 'Male',
    'ugla': 'Female', 'aivars': 'Male', 'dimitar': 'Male',
    'meera': 'Female', 'arjun': 'Male', 'rohan': 'Male',
    'pratham': 'Male', 'venkatesh': 'Male', 'priyamvada': 'Female',
    'padmavathi': 'Female', 'rapunzelina': 'Female',
    'reza_ibrahim': 'Male', 'amir': 'Male',
  };

  /// Total download size in bytes (model + config).
  int get totalSizeBytes => files.values.fold(0, (sum, f) => sum + f.sizeBytes);

  /// Human-readable size.
  String get sizeLabel {
    final mb = totalSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// The .onnx.json config file path.
  String? get configFilePath {
    final entry = files.entries
        .where((e) => e.key.endsWith('.onnx.json'))
        .firstOrNull;
    return entry?.key;
  }
}

class PiperVoiceFile {
  final int sizeBytes;
  final String md5Digest;

  PiperVoiceFile({required this.sizeBytes, required this.md5Digest});
}

/// Manages downloading and listing Piper TTS voice models.
class VoiceManager extends ChangeNotifier {
  static const String _catalogUrl =
      'https://huggingface.co/rhasspy/piper-voices/resolve/main/voices.json';
  static const String _fileBaseUrl =
      'https://huggingface.co/rhasspy/piper-voices/resolve/main/';

  List<PiperVoice> _catalog = [];
  List<PiperVoice> get catalog => _catalog;

  bool _isLoadingCatalog = false;
  bool get isLoadingCatalog => _isLoadingCatalog;

  final StorageService _storageService;

  VoiceManager(this._storageService);

  // Download progress per voice key
  final Map<String, double> _downloadProgress = {};
  double getDownloadProgress(String voiceKey) =>
      _downloadProgress[voiceKey] ?? 0.0;
  bool isDownloading(String voiceKey) =>
      _downloadProgress.containsKey(voiceKey);

  Future<String> get _rootPath async =>
      _storageService.rootPath ??
      (await getApplicationDocumentsDirectory()).path;

  /// Get the directory where voice metadata is stored. Since the sidecar
  /// retirement this holds only the small `.onnx.json` config per voice
  /// (the installed-voice registry); the audio models themselves are the
  /// sherpa re-exports under `system/piper_models/sherpa/`. Legacy rhasspy
  /// `.onnx` files may still sit here until the cleanup UI reclaims them.
  Future<Directory> get voicesDir async {
    final dir = Directory(p.join(await _rootPath, 'system', 'piper_voices'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Fetch the voice catalog from HuggingFace. HF's CDN intermittently
  /// serves 504 error pages, so this retries, and the last good copy is
  /// kept on disk as a fallback — a stale catalog beats an empty browser.
  Future<void> fetchCatalog() async {
    _isLoadingCatalog = true;
    notifyListeners();

    try {
      String? body;
      for (var attempt = 0; attempt < 3 && body == null; attempt++) {
        if (attempt > 0) await Future.delayed(Duration(seconds: attempt));
        try {
          final response = await http.get(Uri.parse(_catalogUrl));
          if (response.statusCode == 200) body = response.body;
        } catch (_) {}
      }
      final cacheFile = File(p.join((await voicesDir).path, 'catalog.json'));
      if (body != null) {
        _catalog = _parseCatalog(body);
        if (_catalog.isNotEmpty) {
          try {
            await cacheFile.writeAsString(body);
          } catch (_) {}
        }
      }
      if (_catalog.isEmpty && cacheFile.existsSync()) {
        print('Voice catalog fetch failed — using the cached copy');
        _catalog = _parseCatalog(await cacheFile.readAsString());
      }
    } catch (e) {
      print('Error fetching voice catalog: $e');
    } finally {
      _isLoadingCatalog = false;
      notifyListeners();
    }
  }

  /// Parses voices.json. Malformed entries are skipped instead of losing
  /// the whole catalog; a non-JSON body (CDN error page) yields [].
  /// Shared by the network fetch and the on-disk cache fallback.
  List<PiperVoice> _parseCatalog(String body) {
    try {
      final Map<String, dynamic> json = jsonDecode(body);
      final voices = <PiperVoice>[];
      for (final e in json.entries) {
        try {
          final data = e.value as Map<String, dynamic>;
          final lang = data['language'] as Map<String, dynamic>;
          final filesRaw = data['files'] as Map<String, dynamic>;
          final files = filesRaw.map(
            (k, v) => MapEntry(
              k,
              PiperVoiceFile(
                sizeBytes: v['size_bytes'] ?? 0,
                md5Digest: v['md5_digest'] ?? '',
              ),
            ),
          );

          voices.add(
            PiperVoice(
              key: data['key'] ?? e.key,
              name: data['name'] ?? '',
              languageCode: lang['code'] ?? '',
              languageEnglish: lang['name_english'] ?? '',
              countryEnglish: lang['country_english'] ?? '',
              quality: data['quality'] ?? '',
              numSpeakers: data['num_speakers'] ?? 1,
              files: files,
            ),
          );
        } catch (_) {
          // Skip the malformed entry, keep the rest of the catalog.
        }
      }
      return voices;
    } catch (_) {
      return [];
    }
  }

  /// List voice keys that are installed locally. Keyed on the `.onnx.json`
  /// config (what installs write now); bare legacy `.onnx` files still
  /// count so nobody's voice list changes when the cleanup UI reclaims the
  /// big legacy models but keeps the configs.
  Future<List<String>> listInstalledVoices() async {
    final dir = await voicesDir;
    final installed = <String>[];

    if (!await dir.exists()) return installed;

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      String? key;
      if (entity.path.endsWith('.onnx.json')) {
        key = p.basename(entity.path);
        key = key.substring(0, key.length - '.onnx.json'.length);
      } else if (entity.path.endsWith('.onnx')) {
        key = p.basenameWithoutExtension(entity.path);
      }
      if (key != null && !installed.contains(key)) installed.add(key);
    }
    return installed;
  }

  /// Returns installed Piper voices (including manually added custom voices)
  /// as properly typed TtsVoiceInfo objects with engine: 'piper'.
  ///
  /// Custom voices (not from the official catalog) get minimal metadata.
  Future<List<TtsVoiceInfo>> getInstalledPiperVoicesAsTtsVoiceInfo() async {
    final keys = await listInstalledVoices();
    return keys.map((key) {
      // Best-effort: check if this key exists in the official catalog for richer metadata
      final catalogVoice = _catalog.where((v) => v.key == key).firstOrNull;

      return TtsVoiceInfo(
        id: key,
        name: catalogVoice?.name ?? key,
        gender: catalogVoice?.gender ?? 'Unknown',
        language: catalogVoice != null
            ? '${catalogVoice.languageEnglish} (${catalogVoice.countryEnglish})'
            : 'Unknown',
        engine: 'piper',
      );
    }).toList();
  }

  /// Check if a specific voice is installed.
  Future<bool> isVoiceInstalled(String voiceKey) async {
    final dir = await voicesDir;
    return File(p.join(dir.path, '$voiceKey.onnx.json')).existsSync() ||
        File(p.join(dir.path, '$voiceKey.onnx')).existsSync();
  }

  /// Install a voice: the small `.onnx.json` config registers it in the
  /// voice list, then the sherpa re-export (the model that actually
  /// speaks, ~60–100MB) downloads eagerly so the first playback isn't a
  /// surprise wait. Returns false — with nothing left behind — when the
  /// voice has no sherpa export and therefore can't be played.
  Future<bool> downloadVoice(String voiceKey) async {
    final voice = _catalog.where((v) => v.key == voiceKey).firstOrNull;
    if (voice == null) return false;

    final configPath = voice.configFilePath;
    if (configPath == null) return false;

    _downloadProgress[voiceKey] = 0.0;
    notifyListeners();

    try {
      final dir = await voicesDir;
      final configFile = File(p.join(dir.path, '$voiceKey.onnx.json'));
      await _downloadFile('$_fileBaseUrl$configPath', configFile, (_) {});

      final ok = await SherpaPiperEngine.ensureVoice(
        await _rootPath,
        voiceKey,
        onProgress: (fraction) {
          _downloadProgress[voiceKey] = fraction;
          notifyListeners();
        },
      );
      if (!ok) {
        // No sherpa export → the voice can never play. Don't leave a
        // config that would list an unplayable voice.
        print('Voice $voiceKey has no sherpa export — not installable');
        if (await configFile.exists()) await configFile.delete();
      }
      _downloadProgress.remove(voiceKey);
      notifyListeners();
      return ok;
    } catch (e) {
      print('Error downloading voice $voiceKey: $e');
      _downloadProgress.remove(voiceKey);
      notifyListeners();
      return false;
    }
  }

  /// Delete an installed voice: the config, any legacy rhasspy `.onnx`,
  /// and the sherpa model bundle.
  Future<void> deleteVoice(String voiceKey) async {
    final dir = await voicesDir;
    final onnxFile = File(p.join(dir.path, '$voiceKey.onnx'));
    final configFile = File(p.join(dir.path, '$voiceKey.onnx.json'));

    if (await onnxFile.exists()) await onnxFile.delete();
    if (await configFile.exists()) await configFile.delete();
    final sherpaDir = Directory(
      SherpaPiperEngine.modelDir(await _rootPath, voiceKey),
    );
    if (await sherpaDir.exists()) await sherpaDir.delete(recursive: true);
    notifyListeners();
  }

  /// Download a file with progress callback.
  Future<void> _downloadFile(
    String url,
    File destFile,
    Function(int received) onProgress,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    final sink = destFile.openWrite();
    int received = 0;

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress(received);
    }

    await sink.close();
  }
}
