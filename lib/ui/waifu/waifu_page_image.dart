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

part of 'waifu_page.dart';

extension _WaifuPageImage on _WaifuPageState {
  Future<void> _attachImage() async {
    final bytes = await pickChatImageAttachment();
    if (bytes == null || !mounted) return;
    await _acceptImageBytes(bytes);
  }

  Future<void> _acceptImageBytes(Uint8List bytes) async {
    rebuildState(() {
      _pendingImage = bytes;
      _pendingVisionOk = null;
      _pendingBlindReason = null;
    });
    LLMProvider? llm;
    StorageService? storage;
    try {
      llm = Provider.of<LLMProvider>(context, listen: false);
      storage = Provider.of<StorageService>(context, listen: false);
    } catch (_) {
      return;
    }
    final isLocal = llm.activeBackend == BackendType.kobold;
    final support = await VisionSupportResolver.instance.resolveForActiveLlm(
      backend: llm.activeBackend,
      storage: storage,
    );
    if (!mounted || _pendingImage == null) return;
    rebuildState(() {
      _pendingVisionOk = support.supported;
      _pendingBlindReason = support.supported
          ? null
          : (support.source == VisionSource.unknown
                ? 'vision support couldn\'t be verified (the server didn\'t '
                      'answer the check), so the photo is described offline '
                      'instead'
                : (isLocal
                      ? 'your local model has no vision projector (mmproj) '
                            'loaded, so it processes text only'
                      : 'the selected API model is text-only and doesn\'t '
                            'accept images'));
    });
  }
}
