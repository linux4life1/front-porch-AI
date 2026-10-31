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
}) async {
  final storage = Provider.of<StorageService>(context, listen: false);
  if (wasAllowed || !storage.realismSettings.afterglowEnabled) return;
  final offer = ExistingChatsOffer(
    liveDatabase(context),
    Provider.of<ChatService>(context, listen: false),
  );
  final int count;
  try {
    count = await offer.countAfterglowOff();
  } catch (e) {
    debugPrint('[PorchLife] could not count chats with Afterglow off: $e');
    return;
  }
  if (count == 0 || !context.mounted) return;
  final turnOn = await showWarmDialog<bool>(
    context,
    title: 'Afterglow is on',
    icon: Icons.local_fire_department,
    accent: AppColors.lustAccentOf(context),
    width: 380,
    content: ExistingChatsOfferBody(count: count),
  );
  if (turnOn != true) return;
  try {
    await offer.turnAfterglowOn();
  } catch (e) {
    debugPrint('[PorchLife] could not turn Afterglow on in existing chats: $e');
  }
}

/// The question's body: what new chats do, one switch for the [count] chats
/// that have it off (starting off), and Done, which answers with the switch.
class ExistingChatsOfferBody extends StatefulWidget {
  const ExistingChatsOfferBody({super.key, required this.count});

  final int count;

  @override
  State<ExistingChatsOfferBody> createState() => _ExistingChatsOfferBodyState();
}

class _ExistingChatsOfferBodyState extends State<ExistingChatsOfferBody> {
  bool _turnOn = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "New chats start with Afterglow unless their character's card "
          'says otherwise.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _turnOn,
          activeThumbColor: AppColors.lustAccentOf(context),
          onChanged: (v) => setState(() => _turnOn = v),
          title: Text(
            n == 1
                ? 'Turn it on in that chat too'
                : 'Turn it on in those $n chats too',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
          subtitle: Text(
            "Only each chat's Afterglow switch changes. Cards stay as they "
            'are, and any chat can switch it off again.',
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
            onPressed: () => Navigator.of(context).pop(_turnOn),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
