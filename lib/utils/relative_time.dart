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

/// "just now", "12m ago", "3h ago", "yesterday", "4 days ago", "Aug 12".
/// Same wording the web shelf uses (web_ui/src/pages/story/relativeTime.ts).
String formatRelativeTime(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24 && at.day == n.day) return '${diff.inHours}h ago';
  final days = DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final year = at.year == n.year ? '' : ' ${at.year}';
  return '${months[at.month - 1]} ${at.day}$year';
}
