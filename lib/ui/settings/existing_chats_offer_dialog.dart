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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/existing_chats_offer.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// After a Porch Life switch is saved: when it has just made Afterglow
/// allowed ([wasAllowed] is the value before the change), ask whether to turn
/// it on in the chats that have their own switch off. Nothing is asked when
/// there are none, and nothing changes unless the switch is flipped.
Future<void> offerAfterglowInExistingChats(
  BuildContext context, {
  required bool wasAllowed,
}) => _offer(context, ExistingChatsFeature.afterglow, wasAllowed: wasAllowed);

/// The same question once Porch Life's Needs is turned on.
Future<void> offerNeedsInExistingChats(
  BuildContext context, {
  required bool wasAllowed,
}) => _offer(context, ExistingChatsFeature.needs, wasAllowed: wasAllowed);

/// The same question once Porch Life allows the Realism Engine again.
Future<void> offerRealismInExistingChats(
  BuildContext context, {
  required bool wasAllowed,
}) => _offer(context, ExistingChatsFeature.realism, wasAllowed: wasAllowed);

/// The library's cards, for each 1:1 chat's card choice; none where the
/// screen has no library (a card then reads as having made no choice).
List<CharacterCard> _libraryOf(BuildContext context) {
  try {
    return Provider.of<CharacterRepository>(context, listen: false).characters;
  } catch (e) {
    debugPrint('[PorchLife] no character library here: $e');
    return const [];
  }
}

bool _allowed(StorageService storage, ExistingChatsFeature feature) =>
    existingChatsFeatureAllowed(storage.realismSettings, feature);

Future<void> _offer(
  BuildContext context,
  ExistingChatsFeature feature, {
  required bool wasAllowed,
}) async {
  final storage = Provider.of<StorageService>(context, listen: false);
  if (wasAllowed || !_allowed(storage, feature)) return;
  final offer = ExistingChatsOffer(
    liveDatabase(context),
    Provider.of<ChatService>(context, listen: false),
    cards: _libraryOf(context),
    realism: storage.realismSettings,
  );
  final int count;
  try {
    count = await offer.countOff(feature);
  } catch (e) {
    debugPrint(
      '[PorchLife] could not count chats with ${feature.name} off: $e',
    );
    return;
  }
  if (count == 0 || !context.mounted) return;
  final turnOn = await showWarmDialog<bool>(
    context,
    title: '${_nameOf(feature)} is on',
    icon: switch (feature) {
      ExistingChatsFeature.needs => Icons.favorite_border,
      ExistingChatsFeature.afterglow => Icons.local_fire_department,
      ExistingChatsFeature.realism => Icons.theater_comedy,
    },
    accent: _accentOf(context, feature),
    width: 380,
    content: ExistingChatsOfferBody(count: count, feature: feature),
  );
  // Porch Life may have stopped allowing it while the question was open.
  if (turnOn != true || !_allowed(storage, feature)) return;
  try {
    await offer.turnOn(feature);
  } catch (e) {
    debugPrint('[PorchLife] could not turn ${feature.name} on in chats: $e');
  }
}

String _nameOf(ExistingChatsFeature feature) => switch (feature) {
  ExistingChatsFeature.needs => 'Needs',
  ExistingChatsFeature.afterglow => 'Afterglow',
  ExistingChatsFeature.realism => 'Realism',
};

Color _accentOf(BuildContext context, ExistingChatsFeature feature) =>
    switch (feature) {
      ExistingChatsFeature.needs => AppColors.porchAmberOf(context),
      ExistingChatsFeature.afterglow => AppColors.lustAccentOf(context),
      ExistingChatsFeature.realism => AppColors.porchTerracottaOf(context),
    };

/// The question's body: what new chats do, one switch for the [count] chats
/// that have it off (starting off), and Done, which answers with the switch.
class ExistingChatsOfferBody extends StatefulWidget {
  const ExistingChatsOfferBody({
    super.key,
    required this.count,
    this.feature = ExistingChatsFeature.afterglow,
  });

  final int count;
  final ExistingChatsFeature feature;

  @override
  State<ExistingChatsOfferBody> createState() => _ExistingChatsOfferBodyState();
}

class _ExistingChatsOfferBodyState extends State<ExistingChatsOfferBody> {
  bool _turnOn = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    final name = _nameOf(widget.feature);
    final accent = _accentOf(context, widget.feature);
    // One eval per such chat, when it is opened, not a burst now.
    final firstOpen = widget.feature == ExistingChatsFeature.realism
        ? ' A chat that never ran it reads where things stand the next time '
              'you open it.'
        : '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.feature == ExistingChatsFeature.realism
              // A card's Realism is off unless it asks, so new chats follow
              // the card or the group, or "Start every new chat with it".
              ? "New chats start with Realism when their character's card, "
                    "or a group chat's group, turns it on, or when Start "
                    'every new chat with Realism is on.'
              : "New chats start with $name unless their character's card, "
                    "or a group chat's group, says otherwise.",
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _turnOn,
          activeThumbColor: accent,
          onChanged: (v) => setState(() => _turnOn = v),
          title: Text(
            n == 1
                ? 'Turn it on in that chat too'
                : 'Turn it on in those $n chats too',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
          subtitle: Text(
            "Only each chat's $name switch changes. Cards stay as they are, "
            'and any chat can switch it off again.$firstOpen',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent),
            onPressed: () => Navigator.of(context).pop(_turnOn),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
