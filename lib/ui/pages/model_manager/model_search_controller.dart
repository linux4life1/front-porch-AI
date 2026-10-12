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

import 'package:flutter/widgets.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

/// The Model Manager's HuggingFace search state: the query field, the
/// results with their file lists, and the in-flight / error flags. Owned by
/// the page so a search survives switching tabs; listeners rebuild on every
/// change.
class ModelSearchController extends ChangeNotifier {
  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();

  List<HFModel> _results = [];
  Map<String, HFModel> _modelsWithFiles = {};
  bool _isSearching = false;
  String? _error;
  bool _disposed = false;

  List<HFModel> get results => _results;
  Map<String, HFModel> get modelsWithFiles => _modelsWithFiles;
  bool get isSearching => _isSearching;
  String? get error => _error;

  /// Search HuggingFace for the field's text, then fetch every hit's files.
  Future<void> search(ModelManager modelManager) async {
    final query = textController.text.trim();
    if (query.isEmpty) return;

    _isSearching = true;
    _results = [];
    _modelsWithFiles = {};
    _error = null;
    notifyListeners();

    try {
      final results = await modelManager.searchHFModels(query);

      if (results.isEmpty) {
        _isSearching = false;
        notifyListeners();
        return;
      }

      // Fetch files for all results
      final modelsWithFiles = await modelManager.fetchFilesForModels(results);

      if (!_disposed) {
        _results = results;
        _modelsWithFiles = modelsWithFiles;
        _isSearching = false;
        notifyListeners();
      }
    } catch (e) {
      if (!_disposed) {
        _isSearching = false;
        _error = 'Search failed: $e';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
