// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'studio_civitai_card.dart';

/// One LoRA's page: the full picture, CivitAI's write-up, and Download.
class StudioCivitaiDetail extends StatefulWidget {
  const StudioCivitaiDetail({
    super.key,
    required this.row,
    required this.adult,
    required this.onDownload,
  });

  final CivitaiModelRow row;
  final bool adult;
  final VoidCallback onDownload;

  @override
  State<StudioCivitaiDetail> createState() => _StudioCivitaiDetailState();
}

class _StudioCivitaiDetailState extends State<StudioCivitaiDetail> {
  late CivitaiModelRow _row = widget.row;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final store = await CivitaiCredentialStore.open();
      final token = await store.readFor(
        accountId: 'local',
        adult: widget.adult,
      );
      final response = await http
          .get(
            civitaiModelUri(widget.row.id, adult: widget.adult),
            headers: {if (token != null) 'Authorization': civitaiBearer(token)},
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted || response.statusCode != 200) return;
      final parsed = parseCivitaiModel(response.body, includeAdult: true);
      if (parsed == null || !mounted) return;
      setState(() => _row = parsed);
    } catch (e) {
      debugPrint('civitai detail failed: ${e.runtimeType}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = _row.imageUrls.isEmpty
        ? [if (_row.previewUrl != null) _row.previewUrl!]
        : _row.imageUrls;
    final hero = images.isEmpty ? null : images.first;
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        _row.name,
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hero != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    hero,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) =>
                        const SizedBox(height: 160),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                studioDownloadCount(_row.downloads),
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              if (_row.filename != null)
                Text(
                  _row.filename!,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                _row.description.isEmpty
                    ? (_loading
                          ? 'Loading the CivitAI description…'
                          : 'CivitAI did not send a description.')
                    : _row.description,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  height: 1.4,
                ),
              ),
              if (images.length > 1) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 96,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final url in images.skip(1))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              url,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: widget.onDownload,
          child: const Text('Download'),
        ),
      ],
    );
  }
}
