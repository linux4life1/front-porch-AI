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

// Barrel for chat-specific extracted widgets (opportunistic per policy; high-freq surface for chat_page).
// Niche ones can be direct imported too.

export 'bubbles/message_bubble.dart';
export 'bubbles/styled_chat_message.dart';
export 'bubbles/external_image_widget.dart';

// Warm-porch sidebar (grouped accordions; panels are direct-import per policy)
export 'sidebar/porch_accordion.dart';
export 'sidebar/sidebar_body.dart';
export 'sidebar/sidebar_tokens.dart';
export 'sidebar/emoji_burst.dart';
export 'sidebar/journal_memory/summary_section.dart';
export 'sidebar/story_tools/author_note_section.dart';
export 'sidebar/story_tools/lorebook_panel.dart';

export 'overlays/rag_setup_dialog.dart';
export 'overlays/realism_processing_overlay.dart';
export 'overlays/objective_check_overlay.dart';
export 'overlays/generation_status_bar.dart';

export 'widgets/chat_image_attachment.dart';
export 'widgets/eval_pill.dart';
export 'widgets/generating_image_bubble.dart';
export 'widgets/look_chevrons.dart';
export 'widgets/mention_autocomplete.dart';
export 'widgets/message_jump.dart';
export 'widgets/settings_menu_item.dart';
