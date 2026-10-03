// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'expression_pack_dialog.dart';

/// Run the whole flow. Returns true iff a pack was imported.
Future<bool> _launchExpressionPack(
  BuildContext context, {
  required String characterDbId,
  required String characterName,
  required CharacterRepository repository,
  required Uint8List? candidateBase,
  required String basePrompt,
  required String negativePrompt,
}) async {
  // Capture providers before any async gap.
  final storage = Provider.of<StorageService>(context, listen: false);
  final imageGen = Provider.of<ImageGenService>(context, listen: false);

  // The same decision the pack will be started with: a ComfyUI Edit graph
  // that is not ready, or a remote API without an edit model, stops here
  // with the reason instead of quietly making the pack some other way.
  final plan = await planExpressionPack(storage);
  if (!context.mounted) return false;
  if (!plan.canStart) {
    await showWarmDialog(
      context,
      title: 'Expression pack can’t start',
      icon: Icons.theater_comedy,
      accent: AppColors.formMasterAccent,
      content: WarmDialogText(plan.refusal!),
      actions: [warmDialogCancel(context, label: 'Got it')],
    );
    return false;
  }

  // Base portrait: the studio's current result/reference when it has one
  // (style-matched to what the user is making right now), else the
  // character's existing avatar (prime expression avatar, falling back to
  // the main card portrait).
  final base =
      candidateBase ??
      await _primeAvatarBytes(
        repository,
        storage,
        characterDbId,
        characterName,
      );
  if (!context.mounted) return false;
  if (base == null) {
    await showWarmDialog(
      context,
      title: 'No base portrait',
      icon: Icons.theater_comedy,
      accent: AppColors.formMasterAccent,
      content: const WarmDialogText(
        'This character has no avatar image yet — generate a portrait in '
        'the Studio (or set a card avatar) first; the pack is built from '
        'a base image.',
      ),
      actions: [warmDialogCancel(context, label: 'Got it')],
    );
    return false;
  }

  // Fully automatic base prep — no crop step (maintainer decision: zero
  // friction; the pack must simply match the avatar's shape). The
  // normalizer preserves the source aspect ratio, so the generated
  // expressions look like the avatar the user already sees in the sidebar.
  // Anyone wanting different framing can pick a pre-cropped reference
  // image in the Studio first.
  String? refused;
  final normalized = await preparePackBase(
    base,
    onRefused: (r) => refused = r.message,
  );
  if (!context.mounted) return false;
  if (normalized == null) {
    await showWarmDialog(
      context,
      title: 'Unreadable image',
      icon: Icons.broken_image_outlined,
      content: WarmDialogText(
        refused ??
            'That image could not be decoded — try a different portrait.',
      ),
      actions: [warmDialogCancel(context, label: 'Got it')],
    );
    return false;
  }

  // Labels the character already has — lets the setup default to
  // generating only the MISSING emotions on a second run, instead of
  // regenerating (and, with replace on, overwriting) the kept ones.
  final existingEmotions = (await repository.getAvatarImages(characterDbId))
      .map((a) => (a.label ?? '').toLowerCase())
      .where((l) => l.isNotEmpty)
      .toSet();
  if (!context.mounted) return false;

  final imported = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ExpressionPackDialog._(
      characterDbId: characterDbId,
      characterName: characterName,
      repository: repository,
      storage: storage,
      imageGen: imageGen,
      baseImage: normalized.bytes,
      baseWidth: normalized.width,
      baseHeight: normalized.height,
      note: normalized.converted ? kPackConvertedNote : null,
      basePrompt: basePrompt,
      negativePrompt: negativePrompt,
      existingEmotions: existingEmotions,
    ),
  );
  return imported == true;
}
