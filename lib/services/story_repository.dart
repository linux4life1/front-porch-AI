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

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/story_project.dart' as model;

/// CRUD repository for Porch Stories projects.
///
/// Stores the full [model.StoryProject] as a JSON blob in the `story_projects` table.
/// This matches the existing lorebook/world pattern of storing complex nested
/// structures as JSON blobs in SQLite.
class StoryRepository extends ChangeNotifier {
  AppDatabase _db;
  List<model.StoryProject> _projects = [];
  bool _isLoading = false;

  List<model.StoryProject> get projects => List.unmodifiable(_projects);
  bool get isLoading => _isLoading;

  /// Runs after a project row is deleted, so side files (run log, Director
  /// undo snapshot) go with it. Set by the pipeline.
  Future<void> Function(String id)? onDelete;

  StoryRepository(this._db);

  /// Update the database reference (e.g. after cloud sync replaces the DB file).
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  /// Load all projects from the database.
  Future<void> loadProjects() async {
    _isLoading = true;
    notifyListeners();

    try {
      final rows = await _db.getAllStoryProjects();
      _projects = rows.map((row) {
        final project = model.StoryProject.fromJsonString(row.data);
        project.dbId = row.id;
        return project;
      }).toList();
    } catch (e) {
      debugPrint('[StoryRepo] Error loading projects: $e');
      _projects = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Create a new story project and persist it.
  Future<model.StoryProject> createProject({
    String title = 'Untitled Story',
  }) async {
    final project = model.StoryProject(title: title);
    final id = await _db.insertStoryProject(
      StoryProjectsCompanion(
        title: Value(title),
        data: Value(project.toJsonString()),
      ),
    );
    project.dbId = id;
    _projects.insert(0, project);
    notifyListeners();
    return project;
  }

  /// Save a project (full overwrite of JSON blob). A project that has never
  /// been inserted (dbId == null — the chat-to-story path builds one via
  /// buildChatStoryProject) is INSERTED here, not dropped: the old
  /// `if (dbId == null) return;` silently no-opped, so the desktop dialog
  /// crashed on `project.dbId!` and the web twin returned `{'id': null}` —
  /// the whole chat-to-story feature was dead on both surfaces.
  Future<void> saveProject(model.StoryProject project) async {
    project.updatedAt = DateTime.now();
    project.normalize();
    if (project.dbId == null) {
      final id = await _db.insertStoryProject(
        StoryProjectsCompanion(
          title: Value(project.title),
          data: Value(project.toJsonString()),
        ),
      );
      project.dbId = id;
      _projects.insert(0, project);
      notifyListeners();
      return;
    }
    await _db.updateStoryProject(
      StoryProjectsCompanion(
        id: Value(project.dbId!),
        title: Value(project.title),
        data: Value(project.toJsonString()),
        updatedAt: Value(project.updatedAt),
      ),
    );
    notifyListeners();
  }

  /// Swap in a different object for the same story (Director undo restores
  /// a snapshot) and persist it. Pages re-read by id, so they pick it up.
  Future<void> replaceProject(model.StoryProject project) async {
    final index = _projects.indexWhere((p) => p.dbId == project.dbId);
    if (index == -1) {
      _projects.insert(0, project);
    } else {
      _projects[index] = project;
    }
    await saveProject(project);
  }

  /// Delete a project permanently.
  Future<void> deleteProject(String id) async {
    await _db.deleteStoryProject(id);
    _projects.removeWhere((p) => p.dbId == id);
    notifyListeners();
    await onDelete?.call(id);
  }

  /// Get a project by database ID.
  model.StoryProject? getById(String id) {
    try {
      return _projects.firstWhere((p) => p.dbId == id);
    } catch (_) {
      return null;
    }
  }
}
