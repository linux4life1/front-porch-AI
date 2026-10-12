// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/pages/repository/stoop_card_sections.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_collapsible.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';

/// A 1/N pager over group members; each member's full collapsible field set is
/// rendered with the same builder the solo view uses. [members] is the
/// already-defensively-read list (entries may be any JSON value).
class StoopDetailMemberCarousel extends StatelessWidget {
  final List<dynamic> members;
  final int index;
  final ValueChanged<int> onIndexChanged;

  const StoopDetailMemberCarousel({
    super.key,
    required this.members,
    required this.index,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final idx = index.clamp(0, members.length - 1);
    final rawEntry = members[idx];
    final m = rawEntry is Map
        ? Map<String, dynamic>.from(
            (rawEntry['data'] is Map ? rawEntry['data'] : rawEntry) as Map,
          )
        : <String, dynamic>{};
    final name = (m['name'] ?? 'Member').toString();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: stoopSectionTitleStyle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (members.length > 1) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left, size: 20),
                  color: stoopCream2(context),
                  onPressed: idx > 0 ? () => onIndexChanged(idx - 1) : null,
                ),
                Text(
                  '${idx + 1}/${members.length}',
                  style: TextStyle(color: stoopMute(context)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right, size: 20),
                  color: stoopCream2(context),
                  onPressed: idx < members.length - 1
                      ? () => onIndexChanged(idx + 1)
                      : null,
                ),
              ],
            ],
          ),
          ...stoopStandardSections(context, m, name),
        ],
      ),
    );
  }
}
