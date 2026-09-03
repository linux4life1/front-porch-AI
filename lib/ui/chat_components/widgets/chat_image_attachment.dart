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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/services/caption/local_caption_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Pick a photo to attach to the next chat message and normalize it for the
/// vision transport: long side capped at 1024 (the avatar-import precedent —
/// plenty for any projector, keeps the base64 payload and stored copy small)
/// and re-encoded as PNG so the `data:image/png` content part is truthful for
/// every source format. Decode/resize runs off the UI isolate — a 12 MP phone
/// photo would jank the composer otherwise. Returns null when the user
/// cancels or the file can't be decoded as an image.
Future<Uint8List?> pickChatImageAttachment() async {
  final result = await PickerPrefs.pickFiles(
    category: PickerPrefs.catImage,
    dialogTitle: 'Attach a photo',
    type: FileType.image,
  );
  final raw = await result?.firstBytes();
  if (raw == null) return null;
  return compute(_downscaleToPng, raw);
}

/// Isolate body for [pickChatImageAttachment]: decode → cap long side at
/// 1024 → PNG. Null when the bytes aren't a decodable image.
Uint8List? _downscaleToPng(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return null;
  final longSide = decoded.width >= decoded.height
      ? decoded.width
      : decoded.height;
  final resized = longSide <= 1024
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? 1024 : null,
          height: decoded.width >= decoded.height ? null : 1024,
          interpolation: img.Interpolation.cubic,
        );
  return img.encodePng(resized);
}

/// The pending-attachment strip shown above the chat composer: thumbnail,
/// label, and a remove ✕. When the capability check comes back "this model
/// can't see images" ([visionOk] false) it becomes the LAST-RESORT surface:
/// it explains what happened and why ([blindReason]), and — only then, only
/// here — offers the one-time Photo Understanding download (the offline
/// vision helper that describes the photo in words). If the helper is
/// already installed, a short teal note says the description will be sent.
/// Sending is deliberately never blocked: capability detection can't
/// interrogate externally-started servers, and KoboldCpp degrades gracefully
/// by ignoring the image.
class PendingImageChip extends StatefulWidget {
  const PendingImageChip({
    super.key,
    required this.bytes,
    required this.visionOk,
    required this.onRemove,
    this.blindReason,
  });

  /// The prepared (downscaled PNG) attachment bytes, used for the thumbnail.
  final Uint8List bytes;

  /// Vision verdict for the active model: true = can see, false = blind,
  /// null = still checking (nothing extra shown while unknown).
  final bool? visionOk;

  /// Backend-specific one-liner for WHY the model can't see (e.g. "no vision
  /// projector (mmproj) is loaded"). Shown in the explanation block.
  final String? blindReason;

  final VoidCallback onRemove;

  @override
  State<PendingImageChip> createState() => _PendingImageChipState();
}

class _PendingImageChipState extends State<PendingImageChip> {
  /// "Not now" pressed for THIS attachment — collapse the offer back to the
  /// plain warning (no persistence: the offer belongs to the moment).
  bool _offerDismissed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalCaptionService.instance,
      builder: (context, _) {
        final service = LocalCaptionService.instance;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.surfaceContainerOf(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      widget.bytes,
                      height: 56,
                      width: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Photo attached',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (widget.visionOk == false) ...[
                          const SizedBox(height: 2),
                          _statusLine(service),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.iconSecondary(context),
                    ),
                    tooltip: 'Remove photo',
                    onPressed: widget.onRemove,
                  ),
                ],
              ),
              if (widget.visionOk == false &&
                  !service.isInstalled &&
                  !_offerDismissed)
                _workaroundOffer(context, service),
            ],
          ),
        );
      },
    );
  }

  /// One-line status under "Photo attached" for the blind case.
  Widget _statusLine(LocalCaptionService service) {
    final installed = service.isInstalled;
    return Row(
      children: [
        Icon(
          installed ? Icons.description_outlined : Icons.visibility_off,
          size: 13,
          color: installed ? Colors.tealAccent : Colors.orangeAccent,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            installed
                ? "Model can't see images — a detailed text description "
                      'will be sent instead.'
                : "Your model can't see images — the character will reply "
                      'without seeing this photo.',
            style: TextStyle(
              color: installed ? Colors.tealAccent : Colors.orangeAccent,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  /// The last-resort explanation + offer block: why the model is blind, what
  /// will happen, and the one-time download that works around it. Only shown
  /// in this exact edge case (photo attached + vision check failed + helper
  /// not installed) — never promoted anywhere else in the app.
  Widget _workaroundOffer(BuildContext context, LocalCaptionService service) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.resolve(
          context,
          const Color(0xFF3A2E14),
          const Color(0xFFFDF3D7),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What happened: the app checked whether your current model can '
            'process images, and it can\'t — '
            '${widget.blindReason ?? 'it supports text only'}. '
            'The photo will still appear in the chat, but the character '
            'won\'t know what it shows.',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          if (service.isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: service.downloadProgress,
                minHeight: 6,
                backgroundColor: AppColors.surfaceContainerOf(context),
                color: AppColors.relationshipAccent,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Downloading the vision helper… '
                    '${(service.downloadProgress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: service.cancelDownload,
                  child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ] else ...[
            Text(
              'Workaround: a small vision helper can look at the photo on '
              'your machine (fully offline) and pass the character a '
              'detailed description in words. One-time '
              '${LocalCaptionService.downloadSizeLabel} download; adds a few '
              'seconds per photo.',
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: AppColors.textSecondary(context),
              ),
            ),
            if (service.lastError != null) ...[
              const SizedBox(height: 4),
              Text(
                'Download failed: ${service.lastError}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.orangeAccent,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => service.download(),
                  icon: const Icon(Icons.download, size: 14),
                  label: Text(
                    'Download ${LocalCaptionService.downloadSizeLabel}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.userBubble,
                    foregroundColor: AppColors.textPrimary(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _offerDismissed = true),
                  child: const Text('Not now', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
