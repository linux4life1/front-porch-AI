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

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/backup/backup_manifest.dart';
import 'package:front_porch_ai/services/backup_service.dart';
import 'package:front_porch_ai/services/web/util/util.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// Backups & Restore for the web app, matching the desktop Backups page.
///
/// Every restore from here is staged for the desktop's next launch: the web
/// app cannot reload the desktop's open database or settings in place.
/// Restoring, and downloading a backup with API keys in it, are
/// credential-grade and need the same password (+ TOTP) step-up as tunnel
/// enable. A step-up for an upload rides in headers, since the body is the
/// file.
class WebBackupRoutes {
  WebBackupRoutes(this._deps, Router router) {
    router.get('/api/backups', _list);
    router.post('/api/backups', _create);
    router.delete('/api/backups/pending', _cancelPending);
    router.post('/api/backups/full', _prepareFull);
    router.get('/api/backups/full/<token>', _downloadFull);
    router.post('/api/backups/full/restore', _restoreFull);
    router.post('/api/backups/<id>/restore', _restoreSnapshot);
    router.delete('/api/backups/<id>', _delete);
  }

  final WebServerDeps _deps;

  /// Upload ceiling for a restore. A full backup with a big picture library
  /// is large, but not this large; the cap stops a runaway upload filling
  /// the disk.
  static const int _maxUploadBytes = 16 * 1024 * 1024 * 1024;

  /// Prepared downloads by one-time token. A download link must work from
  /// a plain `<a href>`, so it cannot carry a step-up; the POST that makes
  /// it can.
  final Map<String, ({File file, DateTime expires})> _downloads = {};
  final Random _random = Random.secure();

  Future<Map<String, dynamic>> _state() async {
    final entries = await BackupService.listEntries();
    final pending = await BackupService.pendingRestore();
    return {
      'nightly': isPreRelease,
      'maxSnapshots': BackupService.maxBackups,
      'dailyDays': BackupService.dailyRetentionDays,
      'snapshots': [
        for (final e in entries)
          {
            'id': p.basename(e.file.path),
            'created': e.modified.millisecondsSinceEpoch,
            'size': e.size,
            'hasSettings': e.hasSettings,
          },
      ],
      'pending': pending == null
          ? null
          : {
              'kind': pending.kind.name,
              'created': pending.created.millisecondsSinceEpoch,
              'staged': pending.staged.millisecondsSinceEpoch,
            },
    };
  }

  Future<shelf.Response> _list(shelf.Request request) async =>
      JsonResponse.ok(await _state());

  Future<shelf.Response> _create(shelf.Request request) async {
    final made = await BackupService.createBackup();
    if (made == null) {
      return JsonResponse.error(
        503,
        'Backup could not be created. The database may be busy or the disk '
        'full; try again in a moment.',
      );
    }
    return JsonResponse.ok(await _state());
  }

  Future<BackupEntry?> _entry(String id) async {
    for (final e in await BackupService.listEntries()) {
      if (p.basename(e.file.path) == id) return e;
    }
    return null;
  }

  Future<shelf.Response> _delete(shelf.Request request, String id) async {
    final entry = await _entry(id);
    if (entry == null) return JsonResponse.error(404, 'No such backup');
    await BackupService.deleteBackup(entry.file);
    return JsonResponse.ok(await _state());
  }

  Future<shelf.Response> _cancelPending(shelf.Request request) async {
    await BackupService.cancelPendingRestore();
    return JsonResponse.ok(await _state());
  }

  Future<shelf.Response?> _stepUp(
    shelf.Request request,
    Map<String, dynamic> body,
  ) => denyUnlessSteppedUp(auth: _deps.auth, body: body, request: request);

  Future<shelf.Response> _restoreSnapshot(
    shelf.Request request,
    String id,
  ) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final denied = await _stepUp(request, body);
    if (denied != null) return denied;
    final entry = await _entry(id);
    if (entry == null) return JsonResponse.error(404, 'No such backup');
    try {
      await BackupService.stageSnapshotRestore(
        entry,
        withSettings: body['withSettings'] != false,
      );
    } on FormatException {
      return JsonResponse.badRequest(
        "The settings in that backup can't be read.",
      );
    }
    return JsonResponse.ok(await _state());
  }

  Future<shelf.Response> _prepareFull(shelf.Request request) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final secrets = body['includeSecrets'] == true;
    if (secrets) {
      final denied = await _stepUp(request, body);
      if (denied != null) return denied;
    }
    _dropExpired();
    final dir = await Directory.systemTemp.createTemp('fpai_web_backup_');
    try {
      final out = await BackupService.createFullBackup(
        dir.path,
        includeSecrets: secrets,
      );
      final file = File(out);
      final token = List.generate(
        24,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _downloads[token] = (
        file: file,
        expires: DateTime.now().add(const Duration(minutes: 15)),
      );
      return JsonResponse.ok({
        'token': token,
        'fileName': p.basename(out),
        'size': await file.length(),
      });
    } catch (e) {
      debugPrint('[Backup] web full backup failed: $e');
      await _deleteDir(dir);
      return JsonResponse.error(500, 'The full backup could not be made.');
    }
  }

  Future<shelf.Response> _downloadFull(
    shelf.Request request,
    String token,
  ) async {
    _dropExpired();
    final entry = _downloads.remove(token);
    if (entry == null || !await entry.file.exists()) {
      return JsonResponse.error(404, 'That download has expired.');
    }
    final file = entry.file;
    final length = await file.length();
    final name = p.basename(file.path);
    return shelf.Response.ok(
      file
          .openRead()
          .handleError((Object e) {
            debugPrint('[Backup] download stream failed: $e');
          })
          .transform(
            StreamTransformer<List<int>, List<int>>.fromHandlers(
              handleDone: (sink) {
                sink.close();
                _deleteDir(file.parent);
              },
            ),
          ),
      headers: {
        'Content-Type': 'application/zip',
        'Content-Length': '$length',
        'Content-Disposition':
            "attachment; filename*=UTF-8''${Uri.encodeComponent(name)}",
        'Cache-Control': 'no-store',
      },
    );
  }

  Future<shelf.Response> _restoreFull(shelf.Request request) async {
    final denied = await _stepUp(request, {
      'currentPassword': request.headers['x-current-password'] ?? '',
      'totpCode': request.headers['x-totp-code'],
    });
    if (denied != null) return denied;
    final dir = await Directory.systemTemp.createTemp('fpai_web_restore_');
    final upload = File(
      p.join(dir.path, 'upload${BackupManifest.fileExtension}'),
    );
    try {
      var written = 0;
      final sink = upload.openWrite();
      try {
        await for (final chunk in request.read()) {
          written += chunk.length;
          if (written > _maxUploadBytes) {
            throw const _TooLarge();
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (written == 0) return JsonResponse.badRequest('Empty upload');
      final manifest = await BackupService.stageFullRestore(upload);
      return JsonResponse.ok({
        ...await _state(),
        'restored': {
          'created': manifest.created.millisecondsSinceEpoch,
          'appVersion': manifest.appVersion,
          'files': manifest.fileCount,
          'secrets': manifest.hasSecrets,
        },
      });
    } on _TooLarge {
      return JsonResponse.error(413, 'That file is too large to restore.');
    } on FormatException catch (e) {
      return JsonResponse.badRequest(e.message);
    } catch (e) {
      debugPrint('[Backup] web restore failed: $e');
      return JsonResponse.error(500, 'The restore could not be prepared.');
    } finally {
      await _deleteDir(dir);
    }
  }

  void _dropExpired() {
    final now = DateTime.now();
    final stale = [
      for (final e in _downloads.entries)
        if (e.value.expires.isBefore(now)) e.key,
    ];
    for (final key in stale) {
      final gone = _downloads.remove(key);
      if (gone != null) _deleteDir(gone.file.parent);
    }
  }

  static Future<void> _deleteDir(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('[Backup] could not remove ${dir.path}: $e');
    }
  }
}

class _TooLarge implements Exception {
  const _TooLarge();
}
