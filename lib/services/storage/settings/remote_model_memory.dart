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

import 'remote_api_key_vault.dart';

/// Which memory slot a stored backend name + URL uses. KoboldCpp (and an
/// unset worker) has no remote model, so no slot: nothing is parked or
/// restored there. oMLX has a fixed address, so it never shares the
/// OpenRouter / Nano-GPT URL that stays saved while it is selected.
String remoteModelSlot({required String backend, required String url}) {
  if (backend.isEmpty || backend == 'kobold') return '';
  if (backend == 'omlx') return normalizeRemoteApiUrl(kOmlxApiV1);
  return normalizeRemoteApiUrl(url);
}

/// The last model picked on each remote host, so switching OpenRouter →
/// Nano-GPT → OpenRouter brings back the OpenRouter model instead of an
/// empty picker. Slots come from [remoteModelSlot].
class RemoteModelMemory {
  RemoteModelMemory.decode(String? raw)
    : _vault = RemoteApiKeyVault.decode(raw);

  final RemoteApiKeyVault _vault;

  /// The model last used on [slot], or empty.
  String modelFor(String slot) => slot.isEmpty ? '' : _vault.keyFor(slot);

  /// Record a pick. An explicit blank forgets the slot's model.
  void pick(String slot, String model) {
    if (slot.isEmpty) return;
    _vault.put(slot, model);
  }

  /// Park the live model when leaving [slot]. A blank picker is not a new
  /// last-used id, so it never wipes what was parked there.
  void park(String slot, String model) {
    if (model.trim().isEmpty) return;
    pick(slot, model);
  }

  /// Slot → model, for the web settings snapshot.
  Map<String, String> get bySlot => {
    for (final slot in _vault.urlsWithKeys) slot: _vault.keyFor(slot),
  };

  String encode() => _vault.encode();
}
