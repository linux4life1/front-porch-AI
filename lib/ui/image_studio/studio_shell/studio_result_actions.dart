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

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/image_crop_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Run one Create generate. On no image, `error` carries the service's
/// status (or the thrown message without its `Exception:` prefix).
Future<({Uint8List? bytes, String error})> generateStudioImage(
  ImageGenService service, {
  required String prompt,
  required bool isPortrait,
  required Uint8List? referenceImage,
}) async {
  try {
    final bytes = await service.generateImage(
      prompt: prompt,
      isPortrait: isPortrait,
      referenceImage: referenceImage,
    );
    if (bytes != null) return (bytes: bytes, error: '');
    return (
      bytes: null,
      error: service.statusMessage.isNotEmpty
          ? service.statusMessage
          : 'Generation returned no image',
    );
  } catch (e) {
    return (
      bytes: null,
      error: e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
    );
  }
}

/// Save a Studio result to disk. [onSaving] flips the caller's busy flag; it
/// is only called back while [context] is mounted.
Future<void> saveStudioImage(
  BuildContext context,
  Uint8List bytes, {
  required ValueChanged<bool> onSaving,
}) async {
  onSaving(true);
  final service = Provider.of<ImageGenService>(context, listen: false);
  final path = await service.saveImageToDisk(bytes);
  if (context.mounted) {
    onSaving(false);
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image saved to $path'),
          backgroundColor: AppColors.resolve(
            context,
            AppColors.logReady,
            AppColors.lightBorder,
          ),
        ),
      );
    }
  }
}

/// Accept only applies to portrait subjects → crop then save as an avatar
/// (and as the persona's avatar when [forPersona]). Returns the saved path,
/// or null when cropping was cancelled, saving failed or [context] unmounted.
Future<String?> acceptStudioAvatar(
  BuildContext context,
  Uint8List bytes, {
  required String? characterName,
  required bool forPersona,
  required ValueChanged<bool> onSaving,
}) async {
  onSaving(true);
  final service = Provider.of<ImageGenService>(context, listen: false);
  final croppedBytes = await ImageCropDialog.show(context, imageBytes: bytes);
  if (croppedBytes == null) {
    if (context.mounted) onSaving(false);
    return null;
  }
  final path = await service.saveAvatarToDisk(
    croppedBytes,
    characterName: characterName,
  );
  if (!context.mounted) return null;
  onSaving(false);
  if (path == null) return null;
  if (forPersona) {
    final personaService = Provider.of<UserPersonaService>(
      context,
      listen: false,
    );
    personaService.updatePersona(
      personaService.persona.copyWith(avatarPath: path),
    );
  }
  return path;
}

/// Save [bytes] to the character's Avatar Gallery as a look (no crop).
Future<void> saveStudioLook(
  BuildContext context,
  Uint8List bytes, {
  required String dbId,
  required String name,
  required ValueChanged<bool> onSaving,
  required void Function(String dbId)? onSaved,
}) async {
  onSaving(true);
  try {
    await Provider.of<CharacterRepository>(
      context,
      listen: false,
    ).addLook(dbId, name, bytes);
    // A look is an avatar_images row too, so the existing library-avatars
    // refresh pushes it onto the live card → the gallery + sidebar chevrons
    // pick it up without reopening.
    onSaved?.call(dbId);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved to Avatar Gallery')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save to gallery failed: $e')));
    }
  } finally {
    if (context.mounted) onSaving(false);
  }
}

/// Attach [bytes] + [prompt] to the conversation, then confirm.
Future<void> sendStudioImageToChat(
  BuildContext context,
  Future<void> Function(Uint8List bytes, String prompt) send,
  Uint8List bytes,
  String prompt,
) async {
  await send(bytes, prompt);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Image sent to chat')));
  }
}
