// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'image_studio.dart';

/// Opens the same Image Studio the chat opens, from the Home sidebar. No chat
/// names the character, so the Character subject picks one from the library.
Future<void> showHomeImageStudio(BuildContext context) {
  final llm = context.read<LLMProvider?>()?.activeService;
  return showWarmDialogOf<void>(
    context,
    barrierDismissible: false,
    builder: (_) =>
        HomeImageStudio(llmService: llm?.isReady == true ? llm : null),
  );
}

class HomeImageStudio extends StatefulWidget {
  const HomeImageStudio({super.key, this.llmService});
  final LLMService? llmService;

  @override
  State<HomeImageStudio> createState() => _HomeImageStudioState();
}

class _HomeImageStudioState extends State<HomeImageStudio> {
  CharacterCard? _card;

  Future<bool> _choose() async {
    final repo = context.read<CharacterRepository>();
    final storage = context.read<StorageService>();
    final picked = await showWarmDialogOf<CharacterCard>(
      context,
      builder: (_) => SceneGuestPickerDialog(
        characters: repo.characters.where((c) => c.dbId != null).toList(),
        title: 'Choose a character',
        icon: Icons.face,
        emptyText: 'Your library has no characters yet.',
        resolveImage: (card) => card.imagePath == null
            ? null
            : storage.resolveCharacterImage(card.imagePath!),
      ),
    );
    if (picked == null || !mounted) return false;
    setState(() => _card = picked);
    return true;
  }

  /// A pack import or a saved look lands in the library; reload the card's
  /// avatars so the gallery and expressions show them straight away.
  Future<void> _refreshAvatars(String dbId) async {
    final repo = context.read<CharacterRepository>();
    final fresh = await repo.getAvatarImages(dbId);
    for (final c in [...repo.characters, ?_card]) {
      if (c.dbId == dbId) c.avatarImages = List<AvatarImage>.from(fresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final persona = context.read<UserPersonaService?>()?.persona;
    final card = _card;
    return ImageStudio(
      mode: ImageGenMode.customPrompt,
      characterName: card?.name,
      characterDescription: card?.description,
      characterPersonality: card?.personality,
      characterDbId: card?.dbId,
      characterImagePath: card?.imagePath,
      scenario: card?.scenario,
      personaName: persona?.name,
      personaText: persona?.persona,
      llmService: widget.llmService,
      onChooseCharacter: _choose,
      onExpressionsImported: _refreshAvatars,
    );
  }
}
