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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk_lang_runtime.dart';
import 'package:front_porch_ai/services/desk/desk_sit_down.dart';

class DeskToolChip {
  const DeskToolChip({
    required this.name,
    required this.detail,
    required this.ok,
  });

  final String name;
  final String detail;
  final bool ok;
}

class DeskWriteRecord {
  const DeskWriteRecord({
    required this.relativePath,
    required this.before,
    required this.after,
  });

  final String relativePath;
  final String before;
  final String after;
}

class DeskMessage {
  const DeskMessage({
    required this.isUser,
    required this.text,
    this.chips = const [],
  });

  final bool isUser;
  final String text;
  final List<DeskToolChip> chips;
}

/// In-memory Desk session. Not a chat `sessions` row.
class DeskSession {
  DeskSession({
    required this.folderRoot,
    required this.coworker,
    this.mode = DeskMode.build,
    this.title = '',
    this.langs,
    Set<String>? suggestedLangs,
    List<DeskMessage>? transcript,
  }) : suggestedLangs = suggestedLangs ?? <String>{},
       transcript = transcript ?? <DeskMessage>[];

  final String folderRoot;
  final CharacterCard coworker;
  DeskMode mode;
  String title;
  DeskLangRuntime? langs;
  final Set<String> suggestedLangs;
  final List<DeskMessage> transcript;
  DeskWriteRecord? lastWrite;
  bool running = false;
}
