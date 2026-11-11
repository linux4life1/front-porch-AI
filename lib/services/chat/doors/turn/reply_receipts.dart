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

import 'package:front_porch_ai/services/chat/doors/turn/gen_turn.dart';

/// Stamps what this turn's lookups did onto the reply: the RAG receipt
/// (rag_injection.dart), web / wiki search and tool receipts. Called from the
/// stream phase, the single funnel Standing Mood also uses, so
/// continue/regen/group/guest turns all carry what retrieval did for THIS
/// text. Persisted by the postgen _saveChat with everything else.
void stampTurnReceipts(GenTurn t) {
  final target = t.streamTarget;
  if (t.ragReceipt != null) {
    target.activeMetadata ??= {};
    target.activeMetadata!['rag_receipt'] = t.ragReceipt;
  }
  if (t.searchReceipt != null) {
    target.activeMetadata ??= {};
    target.activeMetadata!['search_receipt'] = t.searchReceipt;
    if (t.searchReceipt!['source'] == 'wiki') {
      target.activeMetadata!['wiki_receipt'] = t.searchReceipt;
    }
  }
  if (t.wikiReceipt != null) {
    target.activeMetadata ??= {};
    target.activeMetadata!['wiki_receipt'] = t.wikiReceipt;
  }
  if (t.toolReceipt != null) {
    target.activeMetadata ??= {};
    target.activeMetadata!['tool_receipt'] = t.toolReceipt;
  }
}
