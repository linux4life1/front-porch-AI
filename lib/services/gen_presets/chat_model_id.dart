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
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/remote_model_memory.dart';

/// The model chat replies come from, as presets see it. The worker (eval)
/// model is never this.
@immutable
class ChatModelId {
  const ChatModelId._(this.key, this.label, {this.localPath, this.remoteId});

  static const none = ChatModelId._('', '');

  /// Stable link key: `local:<file name>` or `remote:<host slot>|<model id>`.
  /// Empty when no model is chosen.
  final String key;

  /// What the user recognizes: the file name without `.gguf`, or the id.
  final String label;

  /// The GGUF on disk, for a local model.
  final String? localPath;

  /// The provider's model id, for a remote model.
  final String? remoteId;

  bool get isEmpty => key.isEmpty;
  bool get isLocal => localPath != null;

  /// The chat model the backend settings point at right now.
  factory ChatModelId.of(BackendSettings b) {
    if (b.backendType == 'kobold' || b.backendType.isEmpty) {
      final path = b.lastUsedModelPath;
      if (path == null || path.trim().isEmpty) return none;
      return ChatModelId.local(path);
    }
    final model = b.remoteModelName.trim();
    if (model.isEmpty) return none;
    final slot = remoteModelSlot(backend: b.backendType, url: b.remoteApiUrl);
    return ChatModelId.remote(slot, model);
  }

  factory ChatModelId.local(String path) {
    final file = p.basename(path.trim());
    final label = file.toLowerCase().endsWith('.gguf')
        ? file.substring(0, file.length - 5)
        : file;
    return ChatModelId._('local:${file.toLowerCase()}', label, localPath: path);
  }

  factory ChatModelId.remote(String slot, String model) =>
      ChatModelId._('remote:$slot|$model', model, remoteId: model);

  @override
  bool operator ==(Object other) => other is ChatModelId && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
