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

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;

/// Byte-range serving that STREAMS a file instead of reading it whole per
/// request. The bundled scene sounds are small enough that the old
/// `_serveMedia` cut a range out of `readAsBytesSync`; a user's own sound
/// can be tens of megabytes, so every range request here opens only the
/// slice it asked for. The 304/ETag path is kept for a revisit.
Future<shelf.Response> serveMediaRanges(
  File file,
  Map<String, String> request, {
  bool head = false,
}) async {
  final stat = file.statSync();
  final tag =
      '"${stat.size.toRadixString(16)}-'
      '${stat.modified.millisecondsSinceEpoch.toRadixString(16)}"';
  final headers = {
    'Content-Type': _contentType(p.basename(file.path).toLowerCase()),
    'Cache-Control': 'no-cache',
    'Accept-Ranges': 'bytes',
    'ETag': tag,
    'Last-Modified': HttpDate.format(stat.modified),
  };
  final match = request['if-none-match'];
  if (match != null &&
      (match.trim() == '*' ||
          match.split(',').map((t) => t.trim()).contains(tag))) {
    return shelf.Response.notModified(headers: headers);
  }
  final len = stat.size;
  final range = request['range'];
  final m = range == null
      ? null
      : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
  if (m == null) {
    return shelf.Response(
      200,
      body: head ? '' : file.openRead(),
      headers: {...headers, 'Content-Length': '$len'},
    );
  }
  final from = int.tryParse(m.group(1)!);
  final to = int.tryParse(m.group(2)!);
  final int start;
  final int end;
  if (from == null) {
    // `bytes=-N`: the last N bytes.
    if (to == null) {
      return shelf.Response(
        200,
        body: head ? '' : file.openRead(),
        headers: {...headers, 'Content-Length': '$len'},
      );
    }
    start = to >= len ? 0 : len - to;
    end = len - 1;
  } else {
    start = from;
    end = to == null || to >= len ? len - 1 : to;
  }
  if (start >= len || start > end) {
    return shelf.Response(
      416,
      headers: {...headers, 'Content-Range': 'bytes */$len'},
    );
  }
  final sliceLen = end - start + 1;
  return shelf.Response(
    206,
    body: head ? '' : file.openRead(start, end + 1),
    headers: {
      ...headers,
      'Content-Range': 'bytes $start-$end/$len',
      'Content-Length': '$sliceLen',
    },
  );
}

String _contentType(String name) {
  if (name.endsWith('.mp3')) return 'audio/mpeg';
  if (name.endsWith('.wav')) return 'audio/wav';
  return 'application/octet-stream';
}
