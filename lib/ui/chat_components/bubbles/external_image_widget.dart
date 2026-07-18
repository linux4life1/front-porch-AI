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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Renders an external image with consent gating. (public rename, extracted)
class ExternalImageWidget extends StatefulWidget {
  final String url;
  final String altText;
  final bool? allowed;
  final Future<bool> Function()? onRequestPermission;

  const ExternalImageWidget({
    super.key,
    required this.url,
    required this.altText,
    required this.allowed,
    required this.onRequestPermission,
  });

  @override
  State<ExternalImageWidget> createState() => _ExternalImageWidgetState();
}

class _ExternalImageWidgetState extends State<ExternalImageWidget> {
  // ignore: unused_field
  bool _loading =
      false; // Kept for potential future loading UI in external image widget
  File? _cachedFile;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.allowed == null && widget.onRequestPermission != null) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await widget.onRequestPermission!.call();
        if (mounted) setState(() => _loading = false);
      });
    } else if (widget.allowed == true) {
      _loadCachedImage();
    }
  }

  @override
  void didUpdateWidget(covariant ExternalImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.allowed == true &&
        oldWidget.allowed != true &&
        _cachedFile == null) {
      _loadCachedImage();
    }
  }

  Future<void> _loadCachedImage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${appDir.path}/image_cache');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
      final hash = widget.url.hashCode.toRadixString(16);
      final uri = Uri.tryParse(widget.url);
      final ext = (uri?.pathSegments.isNotEmpty == true)
          ? '.${uri!.pathSegments.last.split('.').last.split('?').first}'
          : '.png';
      final file = File('${cacheDir.path}/$hash$ext');

      if (await file.exists()) {
        if (mounted) {
          setState(() {
            _cachedFile = file;
            _loading = false;
          });
        }
        return;
      }

      final httpClient = HttpClient();
      try {
        final request = await httpClient.getUrl(Uri.parse(widget.url));
        final response = await request.close();
        if (response.statusCode == 200) {
          final bytes = await consolidateHttpClientResponseBytes(response);
          await file.writeAsBytes(bytes);
          if (mounted) {
            setState(() {
              _cachedFile = file;
              _loading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _error = 'HTTP ${response.statusCode}';
              _loading = false;
            });
          }
        }
      } finally {
        httpClient.close();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Already allowed — show image
    if (widget.allowed == true) {
      if (_cachedFile != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 600),
              child: Image.file(
                _cachedFile!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.broken_image,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Failed to load image',
                          style: TextStyle(
                            color: Colors.redAccent.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
      if (_error != null) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image, color: Colors.redAccent, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Failed to load image',
                  style: TextStyle(
                    color: Colors.redAccent.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return Container(
        width: 300,
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: AppColors.formMasterAccent,
                strokeWidth: 2,
              ),
              SizedBox(height: 8),
              Text(
                'Loading image...',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    // Denied — show subtle blocked indicator
    if (widget.allowed == false) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported,
              size: 14,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(width: 6),
            Text(
              'Image blocked',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    // Waiting for consent dialog — show loading placeholder
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.orangeAccent.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'External image detected...',
              style: TextStyle(
                color: Colors.orangeAccent.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
