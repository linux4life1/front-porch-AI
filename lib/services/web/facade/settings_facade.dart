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

import 'package:front_porch_ai/services/legacy_model_cleanup.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/settings/settings.dart';

/// Read/write adapter over the core generation + backend settings for the web
/// Settings page. Reuses the existing StorageService setters (read live at
/// generation time) and LLMProvider for live backend switching — no new state.
/// Deliberately a focused slice of the huge desktop settings page: backend,
/// model/API, and the most-used sampler values.
class SettingsFacade {
  SettingsFacade(this._storage, this._llm, {ChatService? chat}) : _chat = chat;

  final StorageService _storage;
  final LLMProvider _llm;

  /// Optional: present whenever a chat is open. Porch Life defaults no
  /// longer push into the live conversation (that wiped lived-in Needs).
  /// Sidebar Chat Tools still write the per-chat override.
  final ChatService? _chat;
  ChatService? get boundChat => _chat;

  static const List<String> backends = kWebSettingsBackends;

  /// Live remote API base — used by the settings route to decide whether a
  /// POST would actually change the generation host (step-up gate).
  String get currentRemoteApiUrl => _storage.backendSettings.remoteApiUrl;

  /// Worker-lane remote base — same stolen-session gate as [currentRemoteApiUrl].
  String get currentWorkerRemoteApiUrl => _storage.workerRemoteApiUrl;

  String get currentWorkerKoboldModelPath =>
      _storage.workerKoboldModelPath ?? '';

  String get currentWorkerKoboldKcppsPath =>
      _storage.workerKoboldKcppsPath ?? '';

  late final SettingsReasoning _reasoning = SettingsReasoning(_storage, _llm);
  late final SettingsSnapshot _snapshot = SettingsSnapshot(
    _storage,
    _llm,
    _reasoning,
  );
  late final SettingsWriter _writer = SettingsWriter(
    _storage,
    _llm,
    _reasoning,
  );

  /// Await the local-template verdict so a web GET/POST does not return
  /// generic chips for one round and the truth on the next.
  Future<void> ensureReasoningResolved() => _reasoning.ensureResolved();

  Map<String, dynamic> read() => _snapshot.build();

  /// Dictionary tags the host can actually check, for the web's picker.
  /// Async because it asks the native side, so it cannot live in [read] —
  /// the routes merge it in.
  Future<List<String>> spellCheckLanguages() =>
      DesktopSpellCheckService.availableLanguages();

  /// Why [body] must not be stored, in plain words, or null. Asked before
  /// anything is written, so a refused save changes nothing.
  String? refusal(Map<String, dynamic> body) => _writer.refusal(body);

  Future<void> update(Map<String, dynamic> body) => _writer.update(body);

  /// Legacy-engine model files still on the host's disk (sidecar
  /// retirement cleanup — desktop parity: the Reclaim Disk Space card).
  Future<Map<String, dynamic>> legacyModels() async {
    final root = _storage.rootPath;
    if (root == null) return {'groups': const [], 'totalBytes': 0};
    final groups = await LegacyModelCleanup.scan(root);
    return {
      'groups': [
        for (final g in groups) {'label': g.label, 'bytes': g.bytes},
      ],
      'totalBytes': groups.fold(0, (sum, g) => sum + g.bytes),
    };
  }

  /// Deletes the scanned legacy files (the scan reruns server-side — the
  /// client never supplies paths). Returns bytes freed.
  Future<int> reclaimLegacyModels() async {
    final root = _storage.rootPath;
    if (root == null) return 0;
    return LegacyModelCleanup.reclaim(root);
  }
}
