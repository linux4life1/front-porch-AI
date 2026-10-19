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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/sidebar_tokens.dart';

/// Live embedding-engine status for the Memory (RAG) sidebar — ready,
/// downloading with a real progress bar, missing model with a Download
/// button, or failed with Retry + the actual error. The old panel only
/// painted a 8px dot that said "Model not downloaded" with no way out.
class RagEngineCard extends StatelessWidget {
  final Color accent;

  const RagEngineCard({super.key, required this.accent});

  @override
  Widget build(BuildContext context) {
    final emb = Provider.of<EmbeddingService>(context);
    final (color, title, detail) = _status(context, emb);
    final downloading = emb.isSettingUp;
    final progress = emb.setupProgress;
    final hasProgress = downloading && progress >= 0 && progress <= 1;
    final failed =
        emb.setupError != null ||
        (!emb.isAvailable && emb.modelOnDisk && emb.lastEngineError != null);
    final needsDownload = !emb.isAvailable && !emb.modelOnDisk && !downloading;

    return Container(
      width: double.infinity,
      padding: SidebarTokens.wellPadding,
      decoration: BoxDecoration(
        color: AppColors.sunkenSurfaceOf(context),
        borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
        border: Border.all(
          color: failed
              ? AppColors.bondLowOf(context).withValues(alpha: 0.45)
              : AppColors.borderOf(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (downloading && !hasProgress)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              style: TextStyle(
                fontSize: 10,
                height: 1.35,
                color: failed
                    ? AppColors.bondLowOf(context)
                    : AppColors.textTertiary(context),
              ),
            ),
          ],
          if (downloading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: hasProgress ? progress : null,
                minHeight: 5,
                backgroundColor: AppColors.borderOf(context),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            if (hasProgress) ...[
              const SizedBox(height: 4),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ],
          if (needsDownload || failed) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: emb.isSettingUp
                    ? null
                    : () {
                        emb.clearSetupError();
                        emb.runSetup();
                      },
                icon: Icon(
                  failed ? Icons.refresh : Icons.download,
                  size: 14,
                  color: AppColors.onAccentOf(context),
                ),
                label: Text(
                  failed ? 'Retry setup' : 'Download model (~550 MB)',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.onAccentOf(context),
                  ),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.formAccentOf(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  (Color, String, String?) _status(BuildContext context, EmbeddingService emb) {
    final green = AppColors.bondHighOf(context);
    final amber = AppColors.porchAmberOf(context);
    final red = AppColors.bondLowOf(context);

    if (emb.isAvailable) {
      return (green, 'Memory engine ready', 'Runs fully on this computer.');
    }
    if (emb.isSettingUp) {
      final status = emb.setupStatus.trim();
      return (
        amber,
        'Setting up memory…',
        status.isEmpty ? 'Please wait.' : status,
      );
    }
    if (emb.setupError != null) {
      return (red, 'Setup failed', _friendlyError(emb.setupError!));
    }
    if (emb.modelOnDisk) {
      if (emb.lastEngineError != null) {
        return (
          red,
          'Model found, but it won’t start',
          _friendlyError(emb.lastEngineError!),
        );
      }
      return (amber, 'Starting memory engine…', 'Loading the local model.');
    }
    return (
      amber,
      'Memory model not installed',
      'One free download (~550 MB). Nothing leaves your machine after that.',
    );
  }

  /// Strip StateError/Exception noise so the sidebar shows a human line.
  String _friendlyError(String raw) {
    var s = raw.trim();
    for (final prefix in const ['Bad state: ', 'Exception: ', 'StateError: ']) {
      if (s.startsWith(prefix)) s = s.substring(prefix.length);
    }
    if (s.length > 220) s = '${s.substring(0, 217)}…';
    return s;
  }
}
