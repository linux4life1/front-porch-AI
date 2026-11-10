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

import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

/// The Main Settings popup's rows. The same rows open a 1:1 and a group;
/// Group Settings… joins them in a group only, where it replaced the pinned
/// Group Settings button.
List<PopupMenuEntry<String>> mainSettingsItems({required bool isGroup}) => [
  const PopupMenuItem(
    value: 'edit_character',
    child: SettingsMenuItem(icon: Icons.edit_outlined, label: 'Edit Character'),
  ),
  const PopupMenuItem(
    value: 'expressions',
    child: SettingsMenuItem(
      icon: Icons.photo_library_outlined,
      label: 'Avatar Gallery',
    ),
  ),
  const PopupMenuItem(
    value: 'ui',
    child: SettingsMenuItem(icon: Icons.tune_outlined, label: 'UI Settings'),
  ),
  const PopupMenuDivider(height: 1),
  const PopupMenuItem(
    value: 'chat',
    child: SettingsMenuItem(
      icon: Icons.chat_bubble_outline,
      label: 'Chat Settings',
    ),
  ),
  const PopupMenuItem(
    value: 'model',
    child: SettingsMenuItem(
      icon: Icons.memory_outlined,
      label: 'Model Settings',
    ),
  ),
  const PopupMenuItem(
    value: 'tts',
    child: SettingsMenuItem(
      icon: Icons.volume_up_outlined,
      label: 'TTS Settings',
    ),
  ),
  if (isGroup) ...const [
    PopupMenuDivider(height: 1),
    PopupMenuItem(
      value: 'group_settings',
      child: SettingsMenuItem(icon: Icons.settings, label: 'Group Settings…'),
    ),
  ],
];
