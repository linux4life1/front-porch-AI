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

// Barrel file for the most commonly reused UI widgets.
//
// This barrel is intentionally small and focused on widgets that appear in
// many pages and dialogs. Niche or single-use widgets should still be
// imported directly.
//
// Preferred usage:
//
// ```dart
// import 'package:front_porch_ai/ui/widgets/widgets.dart';
// ```

export 'chip_list_editor.dart';
export 'identity_chip_lists.dart';
export 'work_row.dart';
export 'birthday_row.dart';
export 'ai_engine_status_card.dart';
export 'app_text_field.dart';
export 'engine_status_chip.dart';
export 'folder_character_picker.dart';
export 'realism_form_section.dart';
export 'styled_dropdown.dart';
export 'styled_text_controller.dart';
export 'sidebar.dart';
export 'model_selector.dart';
export 'kcpps_selector.dart';
export 'low_perf_cpu_warning.dart';
export 'log_view.dart';
export 'slider_with_input.dart';
export 'stop_sequence_list.dart';
export 'character_card_grid.dart';
export 'call_overlay.dart';
export 'chance_time_overlay.dart';
export 'warm_card.dart';
export 'warm_dialog.dart';
export 'onnx_download_overlay.dart';
export 'remote_lock_overlay.dart';
export 'setup_overlay.dart';

export 'expanded_editor_dialog.dart';
export 'realism_progress_row.dart';
export 'needs_bar.dart';
export 'fixation_chip.dart';
export 'group_avatar_montage.dart';
export 'group_member_card.dart';
export 'group_member_chips.dart';
export 'banned_phrases_editor.dart';
export 'output_sanitizer_rule_editor.dart';
export 'vision_projector_field.dart';
export 'character_voice_picker.dart';
