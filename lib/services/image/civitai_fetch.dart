// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:path/path.dart' as p;

import 'civitai_client.dart';
import 'civitai_download.dart';

final Set<String> _civitaiDownloads = {};

/// Downloads one planned file straight to disk.
///
/// Bytes go to `path.part` and replace [CivitaiDownloadPlan.path] only after
/// the body finishes. A short body or an HTTP error deletes the part and
/// leaves an existing file alone. A redirect to another host drops the bearer.
Future<void> downloadCivitaiPlan(
  CivitaiDownloadPlan plan, {
  Duration idle = const Duration(minutes: 2),
  void Function(int received, int? total)? onProgress,
}) async {
  final start = plan.uri;
  final path = plan.path;
  final authorization = plan.authorization;
  if (start == null || path == null || authorization == null) {
    throw StateError('refused');
  }
  if (!_civitaiDownloads.add(path)) {
    throw StateError('busy');
  }
  final client = HttpClient();
  final part = File('$path.part');
  IOSink? sink;
  try {
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
          throw StateError('redirect');
        }
        final next = uri.resolve(location);
        headers = civitaiFollowHeaders(
          from: uri,
          to: next,
          authorization: authorization,
        );
        uri = next;
        continue;
      }
      if (status != 200) {
        await response.drain<void>();
        throw StateError('HTTP $status');
      }
      final expected = response.contentLength;
      final total = expected >= 0 ? expected : null;
      onProgress?.call(0, total);
      await part.parent.create(recursive: true);
      sink = part.openWrite();
      var got = 0;
      await for (final chunk in response.timeout(idle)) {
        got += chunk.length;
        sink.add(chunk);
        onProgress?.call(got, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (got == 0 || (expected >= 0 && got != expected)) {
        throw StateError('short');
      }
      await part.rename(path);
      await _noteDrawThingsLora(path);
      return;
    }
    throw StateError('redirect');
  } catch (e) {
    if (sink != null) {
      try {
        await sink.close();
      } catch (_) {}
    }
    if (await part.exists()) {
      await part.delete();
    }
    rethrow;
  } finally {
    _civitaiDownloads.remove(path);
    client.close(force: true);
  }
}

Future<void> _noteDrawThingsLora(String path) async {
  if (p.basename(p.dirname(path)) != 'lora') return;
  await rememberDrawThingsLora(
    Directory(p.dirname(p.dirname(path))),
    p.basename(path),
  );
}
