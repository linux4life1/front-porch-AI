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

import 'package:path/path.dart' as p;

/// What a full backup file holds and which app wrote it. It is the first
/// entry of every `.fpbackup` archive, so a restore can refuse a file it
/// cannot read before touching anything.
class BackupManifest {
  const BackupManifest({
    required this.format,
    required this.appVersion,
    required this.schemaVersion,
    required this.nightly,
    required this.created,
    required this.hasSecrets,
    required this.fileCount,
  });

  /// Archive layout version. Bump only for a change an older reader would
  /// get wrong; new optional entries never need it.
  static const int currentFormat = 1;

  static const String entryName = 'manifest.json';
  static const String databaseEntry = 'database.db';
  static const String settingsEntry = 'settings.json';

  /// User files sit under this folder, at their path below the storage root.
  static const String filesPrefix = 'files/';

  static const String fileExtension = '.fpbackup';

  final int format;
  final String appVersion;
  final int schemaVersion;
  final bool nightly;
  final DateTime created;
  final bool hasSecrets;
  final int fileCount;

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'kind': 'front-porch-backup',
    'format': format,
    'appVersion': appVersion,
    'schemaVersion': schemaVersion,
    'channel': nightly ? 'nightly' : 'stable',
    'created': created.toUtc().toIso8601String(),
    'secrets': hasSecrets,
    'files': fileCount,
  });

  /// Throws [FormatException] for anything that is not a Front Porch backup.
  static BackupManifest decode(String text) {
    final doc = jsonDecode(text);
    if (doc is! Map || doc['kind'] != 'front-porch-backup') {
      throw const FormatException('not a Front Porch backup');
    }
    final format = doc['format'];
    final schema = doc['schemaVersion'];
    final created = DateTime.tryParse('${doc['created']}');
    if (format is! int || schema is! int || created == null) {
      throw const FormatException('backup manifest is incomplete');
    }
    final files = doc['files'];
    return BackupManifest(
      format: format,
      appVersion: '${doc['appVersion'] ?? ''}',
      schemaVersion: schema,
      nightly: doc['channel'] == 'nightly',
      created: created.toLocal(),
      hasSecrets: doc['secrets'] == true,
      fileCount: files is int ? files : 0,
    );
  }

  /// Why this app cannot restore the backup, or null when it can. A backup
  /// from an older app is fine: its database upgrades on open.
  String? refusal({required int currentSchema}) {
    if (format > currentFormat) {
      return 'This backup was made by a newer Front Porch AI '
          '($appVersion). Update the app, then restore it.';
    }
    if (schemaVersion > currentSchema) {
      return 'This backup holds a newer library than this app understands '
          '($appVersion). Update the app, then restore it.';
    }
    return null;
  }
}

/// Paths below the storage root that a full backup leaves out, because the
/// app downloads them again (models, engines, voices' runtimes), rebuilds
/// them (caches), or because they are the backups themselves.
const List<String> kBackupSkippedDirs = [
  'models',
  'koboldcpp_bin',
  'opencode-bin',
  'kobold_admin',
  'cache',
  'Stable-diffusion',
  'Lora',
  'system/whisper_models',
  'system/kokoro_models',
  'system/piper_models',
  'system/caption_model',
  'KoboldManager/backups',
  'KoboldManager/restore',
];

/// Whether [relative] (a `/`-separated path below the storage root) belongs
/// in a full backup. The live database is skipped here because the backup
/// carries a consistent snapshot of it as [BackupManifest.databaseEntry].
bool includeInFullBackup(String relative) {
  final rel = relative.replaceAll('\\', '/');
  for (final dir in kBackupSkippedDirs) {
    if (rel == dir || rel.startsWith('$dir/')) return false;
  }
  final name = p.posix.basename(rel);
  if (rel.startsWith('KoboldManager/') &&
      !rel.substring('KoboldManager/'.length).contains('/') &&
      RegExp(r'\.db(-wal|-shm|-journal)?$').hasMatch(name)) {
    return false;
  }
  if (name.endsWith(BackupManifest.fileExtension)) return false;
  if (name.endsWith('.tmp') || name == 'session_log.txt') return false;
  return true;
}
