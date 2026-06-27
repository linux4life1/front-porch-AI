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

/// Internal barrel for the web-server service facades. Imported by the few
/// assembly sites that wire many facades at once (`web_server_deps.dart`,
/// `web_server_host.dart`) to keep their import blocks to a single line. Route
/// groups keep direct single-file imports (each needs exactly one facade).
///
/// Add new facades here as they are created so the assembly sites never grow a
/// fresh import block.
library;

export 'backend_facade.dart';
export 'character_authoring_facade.dart';
export 'character_facade.dart';
export 'character_library_facade.dart';
export 'chargen_facade.dart';
export 'chat_facade.dart';
export 'chat_tools_facade.dart';
export 'group_facade.dart';
export 'image_facade.dart';
export 'settings_facade.dart';
export 'story_export_facade.dart';
export 'story_facade.dart';
export 'story_snapshot_builder.dart';
export 'voice_facade.dart';
export 'world_facade.dart';
