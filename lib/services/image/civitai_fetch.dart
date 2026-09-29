// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'civitai_client.dart';
import 'civitai_disk.dart';
import 'civitai_download.dart';
import 'civitai_errors.dart';
import 'civitai_safetensors.dart';

/// No single file may be larger than this, whatever CivitAI lists.
const int kCivitaiMaxBytes = 100 * 1024 * 1024 * 1024;

/// Free space that has to remain after the file is written.
const int kCivitaiDiskHeadroom = 512 * 1024 * 1024;

/// Downloads running at once, across the phone and the desktop sheet.
const int kCivitaiMaxActive = 2;

typedef CivitaiFreeBytes = Future<int?> Function(String directory);

const String _kUnsafeFolder =
    'That models folder leads to a system folder, your home folder or the '
    'drive root, so nothing was saved there.';

final Set<String> _activePaths = {};

String _lockKey(String path) => p.normalize(path).toLowerCase();

class _OneDigest implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Downloads one planned file straight to disk and returns where it landed.
///
/// Bytes stream into `path.fpai-part` and move into place only after the size
/// and checksum CivitAI listed both match. Anything else deletes the part
/// and leaves an existing file alone. The bearer goes only to the origin the
/// download started at, and a redirect may only lead to https. Every failure
/// is a [CivitaiDownloadException] with its own kind. [onStarted] runs once
/// everything that can be refused up front has passed, before the first
/// request, so a caller can tell "refused" from "underway".
Future<String> downloadCivitaiPlan(
  CivitaiDownloadPlan plan, {
  Duration idle = const Duration(minutes: 2),
  void Function(int received, int? total)? onProgress,
  CivitaiCancel? cancel,
  CivitaiFreeBytes freeBytes = civitaiFreeDiskBytes,
  VoidCallback? onStarted,
}) async {
  final start = plan.uri;
  final path = plan.path;
  final authorization = plan.authorization;
  if (plan.refused) {
    throw CivitaiDownloadException(
      plan.failure ?? CivitaiFailure.unsafe,
      plan.reason,
    );
  }
  if (start == null || path == null || authorization == null) {
    throw const CivitaiDownloadException(CivitaiFailure.unsafe);
  }
  if (!civitaiHopAllowed(start)) {
    throw const CivitaiDownloadException(CivitaiFailure.redirect);
  }
  final expected = plan.expectedBytes;
  if (expected != null && expected > kCivitaiMaxBytes) {
    throw const CivitaiDownloadException(CivitaiFailure.tooLarge);
  }
  final key = _lockKey(path);
  if (_activePaths.contains(key)) {
    throw const CivitaiDownloadException(CivitaiFailure.busy);
  }
  if (_activePaths.length >= kCivitaiMaxActive) {
    throw const CivitaiDownloadException(CivitaiFailure.tooMany);
  }
  _activePaths.add(key);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final part = File(civitaiPartPath(path));
  RandomAccessFile? out;
  var ownsPart = false;
  try {
    cancel?.onCancel(() => client.close(force: true));
    await _checkTarget(plan, path, expected, freeBytes);
    onStarted?.call();
    var uri = start;
    var headers = civitaiFollowHeaders(
      from: start,
      to: start,
      authorization: authorization,
    );
    for (var hop = 0; hop < 5; hop++) {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(minutes: 10),
      );
      final status = response.statusCode;
      if (status >= 300 && status < 400) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || location.isEmpty) {
          throw const CivitaiDownloadException(CivitaiFailure.redirect);
        }
        final next = uri.resolve(location);
        if (!civitaiHopAllowed(next)) {
          throw const CivitaiDownloadException(CivitaiFailure.redirect);
        }
        headers = civitaiFollowHeaders(
          from: start,
          to: next,
          authorization: authorization,
        );
        uri = next;
        continue;
      }
      if (status != 200) {
        await response.drain<void>();
        throw _statusFailure(status);
      }
      final length = response.contentLength;
      if (length > kCivitaiMaxBytes) {
        throw const CivitaiDownloadException(CivitaiFailure.tooLarge);
      }
      if (expected != null && length >= 0 && length != expected) {
        throw const CivitaiDownloadException(CivitaiFailure.sizeMismatch);
      }
      final total = expected ?? (length >= 0 ? length : null);
      onProgress?.call(0, total);
      await part.parent.create(recursive: true);
      // Append, then lock, then empty it: opening for write would truncate a
      // part that another copy of the app is still filling.
      out = await part.open(mode: FileMode.append);
      try {
        await out.lock(FileLock.exclusive);
      } on FileSystemException {
        throw const CivitaiDownloadException(CivitaiFailure.busy);
      }
      ownsPart = true;
      await out.truncate(0);
      final digest = _OneDigest();
      final hasher = plan.sha256 == null
          ? null
          : sha256.startChunkedConversion(digest);
      final limit = expected ?? kCivitaiMaxBytes;
      var got = 0;
      try {
        await for (final chunk in response.timeout(idle)) {
          if (cancel?.isCancelled ?? false) {
            throw const CivitaiDownloadException(CivitaiFailure.cancelled);
          }
          got += chunk.length;
          if (got > limit) {
            throw CivitaiDownloadException(
              expected == null
                  ? CivitaiFailure.tooLarge
                  : CivitaiFailure.sizeMismatch,
            );
          }
          await out.writeFrom(chunk);
          hasher?.add(chunk);
          onProgress?.call(got, total);
        }
      } on TimeoutException {
        throw const CivitaiDownloadException(CivitaiFailure.stalled);
      } on HttpException {
        throw _cutShort(cancel);
      } on SocketException {
        throw _cutShort(cancel);
      }
      await out.flush();
      await out.close();
      out = null;
      if (got == 0 ||
          (expected != null && got != expected) ||
          (length >= 0 && got != length)) {
        throw const CivitaiDownloadException(CivitaiFailure.short);
      }
      hasher?.close();
      final want = plan.sha256;
      if (want != null && digest.value.toString() != want.toLowerCase()) {
        throw const CivitaiDownloadException(CivitaiFailure.hashMismatch);
      }
      final landed = await _moveIntoPlace(plan, part, path);
      await _noteDrawThingsLora(landed, plan.baseModel);
      return landed;
    }
    throw const CivitaiDownloadException(CivitaiFailure.redirect);
  } catch (e) {
    if (out != null) {
      try {
        await out.close();
      } catch (_) {}
    }
    if (ownsPart && await part.exists()) await part.delete();
    if (e is CivitaiDownloadException) rethrow;
    if (cancel?.isCancelled ?? false) {
      throw const CivitaiDownloadException(CivitaiFailure.cancelled);
    }
    debugPrint('civitai download failed: ${e.runtimeType}');
    throw const CivitaiDownloadException(CivitaiFailure.network);
  } finally {
    _activePaths.remove(key);
    client.close(force: true);
  }
}

/// A connection that dropped mid-body. A cancel closes it on purpose.
CivitaiDownloadException _cutShort(CivitaiCancel? cancel) {
  return CivitaiDownloadException(
    (cancel?.isCancelled ?? false)
        ? CivitaiFailure.cancelled
        : CivitaiFailure.short,
  );
}

CivitaiDownloadException _statusFailure(int status) {
  switch (status) {
    case 401:
      return const CivitaiDownloadException(CivitaiFailure.keyRefused);
    case 403:
      return const CivitaiDownloadException(CivitaiFailure.locked);
    case 404:
      return const CivitaiDownloadException(CivitaiFailure.notFound);
  }
  return CivitaiDownloadException(
    CivitaiFailure.http,
    'CivitAI answered HTTP $status.',
  );
}

/// Everything that can be refused before a byte is requested.
Future<void> _checkTarget(
  CivitaiDownloadPlan plan,
  String path,
  int? expected,
  CivitaiFreeBytes freeBytes,
) async {
  final root = plan.root;
  if (!await civitaiFolderIsSafe(p.dirname(path)) ||
      (root != null && !await civitaiFolderIsSafe(root))) {
    throw const CivitaiDownloadException(CivitaiFailure.unsafe, _kUnsafeFolder);
  }
  _throwIfTaken(path, expected);
  if (expected != null) {
    final free = await freeBytes(p.dirname(path));
    if (free != null && free < expected + kCivitaiDiskHeadroom) {
      throw const CivitaiDownloadException(CivitaiFailure.diskFull);
    }
  }
}

/// Throws when something is already at [path]. The same size as CivitAI lists
/// counts as already installed; anything else is a different file that must
/// not be replaced.
void _throwIfTaken(String path, int? expected) {
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  final same =
      type == FileSystemEntityType.file &&
      (expected == null || File(path).lengthSync() == expected);
  throw CivitaiDownloadException(
    same ? CivitaiFailure.exists : CivitaiFailure.nameTaken,
  );
}

Future<String> _moveIntoPlace(
  CivitaiDownloadPlan plan,
  File part,
  String path,
) async {
  var target = path;
  final allInOne = plan.allInOnePath;
  if (allInOne != null && await safetensorsIsAllInOne(part)) {
    target = allInOne;
    if (!await civitaiFolderIsSafe(p.dirname(target))) {
      throw const CivitaiDownloadException(
        CivitaiFailure.unsafe,
        _kUnsafeFolder,
      );
    }
    await File(target).parent.create(recursive: true);
  }
  _throwIfTaken(target, plan.expectedBytes);
  try {
    await part.rename(target);
  } on FileSystemException {
    await part.copy(target);
    await part.delete();
  }
  return target;
}

/// A part this old that nothing holds open is dead. A running download
/// writes constantly, and stalls end after two minutes.
const Duration kCivitaiPartStaleAfter = Duration(hours: 1);

/// Deletes partial downloads that nothing is writing any more, for example
/// after the app quit mid-download. Only our own `.fpai-part` files, only
/// ones untouched for [olderThan], and never one another running copy of the
/// app holds a lock on. A file that cannot be inspected or removed is left
/// alone and logged. Returns how many were removed.
/// Kinds in [typeFolders] are swept in their own folders.
Future<int> sweepCivitaiParts(
  String root, {
  Duration olderThan = kCivitaiPartStaleAfter,
  Map<String, String> typeFolders = const {},
}) async {
  var removed = 0;
  final cutoff = DateTime.now().subtract(olderThan);
  final dirs = {
    for (final folder in ['', ...kCivitaiFolders])
      civitaiKindFolder(root, folder, typeFolders),
  };
  for (final path in dirs) {
    final dir = Directory(path);
    try {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith(kCivitaiPartSuffix)) {
          continue;
        }
        if (await _sweepOne(entity, cutoff)) removed++;
      }
    } on FileSystemException catch (e) {
      debugPrint(
        'civitai part sweep skipped a folder: ${e.osError?.errorCode}',
      );
    }
  }
  return removed;
}

Future<bool> _sweepOne(File part, DateTime cutoff) async {
  final target = part.path.substring(
    0,
    part.path.length - kCivitaiPartSuffix.length,
  );
  if (_activePaths.contains(_lockKey(target))) return false;
  RandomAccessFile? handle;
  try {
    if ((await part.lastModified()).isAfter(cutoff)) return false;
    handle = await part.open(mode: FileMode.append);
    await handle.lock(FileLock.exclusive);
    await handle.close();
    handle = null;
    await part.delete();
    return true;
  } on FileSystemException catch (e) {
    debugPrint('civitai part left alone: ${e.osError?.errorCode}');
    return false;
  } finally {
    try {
      await handle?.close();
    } on FileSystemException {
      // Already closed or gone.
    }
  }
}

Future<void> _noteDrawThingsLora(String path, String baseModel) async {
  if (p.basename(p.dirname(path)) != 'lora') return;
  await rememberDrawThingsLora(
    Directory(p.dirname(p.dirname(path))),
    p.basename(path),
    baseModel: baseModel,
  );
}
