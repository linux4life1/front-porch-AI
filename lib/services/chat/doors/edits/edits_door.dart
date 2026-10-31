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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/doors/edits/edit_deps.dart';
import 'package:front_porch_ai/services/chat/doors/edits/impersonator.dart';
import 'package:front_porch_ai/services/chat/doors/edits/message_editor.dart';
import 'package:front_porch_ai/services/chat/doors/edits/regen_controller.dart';
import 'package:front_porch_ai/services/chat/doors/edits/reprocessor.dart';
import 'package:front_porch_ai/services/chat/doors/edits/swipe_variants.dart';
import 'package:front_porch_ai/services/chat/doors/edits/token_alts.dart';

export 'package:front_porch_ai/services/chat/doors/edits/edit_deps.dart';
export 'package:front_porch_ai/services/chat/doors/edits/impersonator.dart';
export 'package:front_porch_ai/services/chat/doors/edits/message_editor.dart';
export 'package:front_porch_ai/services/chat/doors/edits/regen_controller.dart';
export 'package:front_porch_ai/services/chat/doors/edits/reprocessor.dart';
export 'package:front_porch_ai/services/chat/doors/edits/swipe_variants.dart';
export 'package:front_porch_ai/services/chat/doors/edits/token_alts.dart';

/// Message operations: edit and delete ([editor]), regenerate ([regen]),
/// swipes and the variant picker ([swipes]), rewrites from a word
/// ([tokenAlts]), Manual Reprocess ([reprocess]) and impersonate
/// ([impersonator]).
///
/// Every rewind these run keys a group's state by the message's speaker id.
/// The edits notify through [EditDeps.notify], the service's own
/// synchronous notify, at the moments they always did: a listener (the
/// Realism overlay, the web chat_updated push) sees each transition, which a
/// coalesced notify would merge. The state the door owns (the Feelings
/// rescore flag and crossings, the rewrite seed, the word odds) has no
/// listener of its own, so the door raises no notification today; the
/// service still forwards it through its coalescing door forwarder.
class EditsDoor extends ChangeNotifier {
  EditsDoor(this._d);

  final EditDeps _d;

  late final MessageEditor editor = MessageEditor(_d);
  late final RegenController regen = RegenController(_d);
  late final SwipeVariants swipes = SwipeVariants(_d, regen);
  late final TokenAlts tokenAlts = TokenAlts(_d, regen);
  late final Reprocessor reprocess = Reprocessor(_d);
  late final Impersonator impersonator = Impersonator(_d);
}
