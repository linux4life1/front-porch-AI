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

// Barrel for the app shell: the pre-runApp startup phases, the provider
// graph, post-first-frame recovery and chores, and the quit path. main.dart
// sequences them; files inside this directory import each other directly.

export 'app_shutdown.dart';
export 'main_window.dart';
export 'post_frame_tasks.dart';
export 'root_providers.dart';
export 'startup_phases.dart';
export 'startup_recovery.dart';
export 'web_server_host_factory.dart';
export 'window_bounds_tracker.dart';
