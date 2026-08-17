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

/// Barrel for the prompt-injection leaves — the fragments that assemble the
/// words-only state block each turn.
///
/// Added 2026-08-07 under the self-extending barrel rule: chat_service.dart
/// hand-wrote FIFTEEN single-file imports from this directory, which is
/// exactly the accumulation the rule exists to stop. Leaves inside this
/// directory still import each other directly (the self-import exemption).
library;

export 'ambition_injection.dart';
export 'author_note_builder.dart';
export 'behavioral_injection.dart';
export 'chaos_injection.dart';
export 'emotion_injection.dart';
export 'inventory_injection.dart';
export 'journal_injection.dart';
export 'needs_injection.dart';
export 'nsfw_injection.dart';
export 'plan_injection.dart';
export 'porch_night_injection.dart';
export 'preferences_injection.dart';
export 'promise_debt_injection.dart';
export 'realism_state_injection.dart';
export 'recap_injection.dart';
export 'relationship_injection.dart';
export 'speaker_resolution.dart';
export 'state_zone_frame.dart';
export 'time_injection.dart';
export 'weather_injection.dart';
export 'world_injection.dart';
