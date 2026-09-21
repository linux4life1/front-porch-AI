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

part of 'update_service.dart';

/// Download the chosen GitHub asset to a temp file.
extension UpdateServiceDownload on UpdateService {
  /// Download the installer to a temp directory.
  /// Does NOT run it — call installNow() or let installOnClose() handle it.
  Future<void> _downloadUpdateImpl() async {
    if (!UpdateService.isSupported || _downloadUrl.isEmpty || _downloading) {
      return;
    }

    _downloading = true;
    _downloadComplete = false;
    _downloadProgress = 0.0;
    notify();

    try {
      final tempDir = Directory.systemTemp;
      // Use the resolved asset name so the temp file has the correct
      // extension for the later install dispatch.
      final assetName = _selectedAssetName.isNotEmpty
          ? _selectedAssetName
          : UpdateService._platformAsset;
      final sep = Platform.isWindows ? '\\' : '/';
      final installerPath = '${tempDir.path}$sep$assetName';
      final file = File(installerPath);

      final request = http.Request('GET', Uri.parse(_downloadUrl));
      final client = http.Client();
      try {
        final response = await client.send(request);
        // A 404/500 HTML error page must never become "the installer":
        // the Linux path deletes the RUNNING AppImage before copying, so a
        // garbage file that passed this point destroyed the install.
        if (response.statusCode != 200) {
          throw Exception('installer download HTTP ${response.statusCode}');
        }

        final totalBytes = response.contentLength ?? 0;
        int receivedBytes = 0;
        final sink = file.openWrite();
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            receivedBytes += chunk.length;
            if (totalBytes > 0) {
              _downloadProgress = receivedBytes / totalBytes;
              notify();
            }
          }
        } finally {
          await sink.close();
        }

        final invalid = UpdateService.validateInstallerDownload(
          receivedBytes: receivedBytes,
          expectedBytes: totalBytes,
        );
        if (invalid != null) throw Exception(invalid);
        // A complete fake 200 (a captive portal / CDN error page big enough
        // to pass the size floor) must still not become the installer: an
        // HTML body is text, real installers are binary. First byte '<' (or
        // a leading doctype after whitespace) = not an installer.
        final head = await file
            .openRead(0, 64)
            .fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        final headText = String.fromCharCodes(head).trimLeft().toLowerCase();
        if (headText.startsWith('<')) {
          throw Exception('installer download is an HTML page, not a binary');
        }

        _pendingInstallerPath = installerPath;
        _downloadComplete = true;
        _downloading = false;
        notify();
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Download error: $e');
      _downloading = false;
      _downloadProgress = 0.0;
      notify();
    }
  }
}
