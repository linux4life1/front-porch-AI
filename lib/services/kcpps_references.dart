// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/story_repository.dart';

/// Moves everything that points at the preset [from] to [to] (after a
/// rename) or, with [to] null, lets go of it (after a delete): the chat
/// preset, each model's preset, the helper model's, and Porch Stories jobs
/// that load their own model with it.
Future<void> repointKcppsPreset({
  required StorageService storage,
  required String from,
  String? to,
  StoryRepository? stories,
}) async {
  bool same(String? path) =>
      path != null &&
      path.isNotEmpty &&
      p.equals(p.normalize(path), p.normalize(from));

  final backend = storage.backendSettings;
  if (same(backend.activeKcppsPath)) await backend.setActiveKcppsPath(to);
  if (same(backend.workerKoboldKcppsPath)) {
    await backend.setWorkerKoboldKcppsPath(to);
  }
  final presets = storage.presetSettings;
  for (final e in presets.modelPresetMap.entries.toList()) {
    if (same(e.value)) await presets.setModelPreset(e.key, to);
  }
  if (stories == null) return;
  for (final project in stories.projects) {
    var moved = false;
    for (final lane in [
      project.planningLane,
      project.proseLane,
      project.reviewLane,
    ]) {
      if (!same(lane.kcpps)) continue;
      lane.kcpps = to ?? '';
      moved = true;
    }
    if (moved) await stories.saveProject(project);
  }
}
