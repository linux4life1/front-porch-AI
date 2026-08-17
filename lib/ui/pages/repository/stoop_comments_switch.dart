// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-card Discussion opt-in switch. Same chrome as StoopAdultSwitch.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Per-card “allow discussion” toggle. Default off. Not a global setting.
class StoopCommentsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  /// When true, the subtitle explains the live kill-switch (hide without
  /// republishing; rows stay). Upload/update uses the opt-in copy.
  final bool liveKill;

  const StoopCommentsSwitch({
    Key? key,
    required this.value,
    required this.onChanged,
    this.liveKill = false,
  }) : super(key: key ?? const Key('stoop-comments-enabled'));

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: stoopCardGradient(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: stoopBorder(context)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          key: const Key('stoop-comments-enabled'),
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.stoopAmber,
          title: Text(
            'Allow discussion on this card',
            style: TextStyle(color: stoopCream(context)),
          ),
          subtitle: Text(
            liveKill
                ? 'Turn off to hide comments without republishing. '
                      'Existing comments are kept.'
                : 'Let people comment on this listing. Off by default.',
            style: TextStyle(color: stoopMute(context), fontSize: 12),
          ),
        ),
      ),
    );
  }
}
