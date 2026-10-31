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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/recovery_block.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Each member's Recovery block in Edit group, while Porch Life allows
/// Afterglow. Like the member's Edit, it saves to the member's own row (the
/// page's Save writes only the group), a moment after the last change, and
/// the open chat's copy of the member follows.
class EditGroupMemberRecovery extends StatefulWidget {
  const EditGroupMemberRecovery({super.key, required this.members});

  final List<CharacterCard> members;

  @override
  State<EditGroupMemberRecovery> createState() =>
      _EditGroupMemberRecoveryState();
}

class _EditGroupMemberRecoveryState extends State<EditGroupMemberRecovery> {
  static const _settle = Duration(milliseconds: 500);
  final Map<String, Timer> _pending = {};
  final Map<String, Future<void> Function()> _writes = {};

  void _changed(CharacterCard member, RecoveryProfile recovery) {
    final id = member.dbId;
    if (id == null || id.isEmpty) return;
    setState(() {
      member.frontPorchExtensions =
          (member.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            recovery: recovery,
          );
    });
    final db = liveDatabase(context);
    final chat = Provider.of<ChatService>(context, listen: false);
    _writes[id] = () => _save(db, chat, member);
    _pending[id]?.cancel();
    _pending[id] = Timer(_settle, () => _flush(id));
  }

  Future<void> _flush(String id) async {
    _pending.remove(id)?.cancel();
    await _writes.remove(id)?.call();
  }

  Future<void> _save(
    AppDatabase db,
    ChatService chat,
    CharacterCard member,
  ) async {
    try {
      await saveGroupMemberExtensions(db, member);
      if (isOpenGroupMember(chat, member)) {
        chat.refreshActiveCharacterCard(member);
      }
    } catch (e) {
      debugPrint('[EditGroup] Recovery for ${member.name} not saved: $e');
    }
  }

  @override
  void dispose() {
    // Leaving the page must not drop the last change.
    for (final id in _pending.keys.toList()) {
      unawaited(_flush(id));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members = [
      for (final m in widget.members)
        if (m.dbId != null && m.dbId!.isNotEmpty) m,
    ];
    if (!afterglowEnabledOf(context) || members.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        for (final m in members)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  RecoveryBlock(
                    key: ValueKey('member-recovery-${m.dbId}'),
                    recovery:
                        m.frontPorchExtensions?.recovery ??
                        RecoveryProfile.auto,
                    sex: m.frontPorchExtensions?.sex ?? '',
                    intimateInto:
                        m.frontPorchExtensions?.intimateInto ?? const [],
                    intimateNotInto:
                        m.frontPorchExtensions?.intimateNotInto ?? const [],
                    onChanged: (r) => _changed(m, r),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
