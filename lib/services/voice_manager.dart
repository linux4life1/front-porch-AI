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

  /// The .onnx file path relative to HuggingFace repo root.
  String? get onnxFilePath {
    final entry = files.entries.where((e) => e.key.endsWith('.onnx')).firstOrNull;
    return entry?.key;
  }

  /// The .onnx.json config file path.
  String? get configFilePath {
    final entry = files.entries.where((e) => e.key.endsWith('.onnx.json')).firstOrNull;
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
  double getDownloadProgress(String voiceKey) => _downloadProgress[voiceKey] ?? 0.0;
  bool isDownloading(String voiceKey) => _downloadProgress.containsKey(voiceKey);

  /// Get the directory where voice models are stored.
  Future<Directory> get voicesDir async {
    final root = _storageService.rootPath ?? (await getApplicationDocumentsDirectory()).path;
    final dir = Directory(p.join(root, 'system', 'piper_voices'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Fetch the voice catalog from HuggingFace.
  Future<void> fetchCatalog() async {
    _isLoadingCatalog = true;
    notifyListeners();

    try {
      final response = await http.get(Uri.parse(_catalogUrl));
      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        _catalog = json.entries.map((e) {
          final data = e.value as Map<String, dynamic>;
          final lang = data['language'] as Map<String, dynamic>;
          final filesRaw = data['files'] as Map<String, dynamic>;
          final files = filesRaw.map((k, v) => MapEntry(k, PiperVoiceFile(
            sizeBytes: v['size_bytes'] ?? 0,
            md5Digest: v['md5_digest'] ?? '',
          )));

          return PiperVoice(
            key: data['key'] ?? e.key,
            name: data['name'] ?? '',
            languageCode: lang['code'] ?? '',
            languageEnglish: lang['name_english'] ?? '',
            countryEnglish: lang['country_english'] ?? '',
            quality: data['quality'] ?? '',
            numSpeakers: data['num_speakers'] ?? 1,
            files: files,
          );
        }).toList();
      }
    } catch (e) {
      print('Error fetching voice catalog: $e');
    } finally {
      _isLoadingCatalog = false;
      notifyListeners();
    }
  }

  /// List voice keys that are downloaded locally.
  Future<List<String>> listInstalledVoices() async {
    final dir = await voicesDir;
    final installed = <String>[];

    if (!await dir.exists()) return installed;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.onnx')) {
        final baseName = p.basenameWithoutExtension(entity.path);
        installed.add(baseName);
      }
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
    final onnxFile = File(p.join(dir.path, '$voiceKey.onnx'));
    return onnxFile.existsSync();
  }

  /// Get the local path to a voice model's .onnx file.
  Future<String> getVoiceModelPath(String voiceKey) async {
    final dir = await voicesDir;
    return p.join(dir.path, '$voiceKey.onnx');
  }

  /// Download a voice model (both .onnx and .onnx.json).
  Future<bool> downloadVoice(String voiceKey) async {
    final voice = _catalog.where((v) => v.key == voiceKey).firstOrNull;
    if (voice == null) return false;

    final onnxPath = voice.onnxFilePath;
    final configPath = voice.configFilePath;
    if (onnxPath == null || configPath == null) return false;

    _downloadProgress[voiceKey] = 0.0;
    notifyListeners();

    try {
      final dir = await voicesDir;
      final totalBytes = voice.totalSizeBytes;
      int downloadedBytes = 0;

      // Download .onnx model
      final onnxUrl = '$_fileBaseUrl$onnxPath';
      final onnxFile = File(p.join(dir.path, '$voiceKey.onnx'));
      await _downloadFile(onnxUrl, onnxFile, (received) {
        downloadedBytes = received;
        _downloadProgress[voiceKey] = totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
        notifyListeners();
      });

      // Download .onnx.json config
      final configUrl = '$_fileBaseUrl$configPath';
      final configFile = File(p.join(dir.path, '$voiceKey.onnx.json'));
      final onnxSize = voice.files[onnxPath]?.sizeBytes ?? 0;
      await _downloadFile(configUrl, configFile, (received) {
        _downloadProgress[voiceKey] = totalBytes > 0 ? (onnxSize + received) / totalBytes : 0.0;
        notifyListeners();
      });

      _downloadProgress.remove(voiceKey);
      notifyListeners();
      return true;
    } catch (e) {
      print('Error downloading voice $voiceKey: $e');
      _downloadProgress.remove(voiceKey);
      notifyListeners();
      return false;
    }
  }

  /// Delete a downloaded voice model.
  Future<void> deleteVoice(String voiceKey) async {
    final dir = await voicesDir;
    final onnxFile = File(p.join(dir.path, '$voiceKey.onnx'));
    final configFile = File(p.join(dir.path, '$voiceKey.onnx.json'));

    if (await onnxFile.exists()) await onnxFile.delete();
    if (await configFile.exists()) await configFile.delete();
    notifyListeners();
  }

  /// Download a file with progress callback.
  Future<void> _downloadFile(String url, File destFile, Function(int received) onProgress) async {
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
