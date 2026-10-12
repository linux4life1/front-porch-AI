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

import 'package:front_porch_ai/services/image/image.dart';

/// Phone JSON for a LoRA family fact. [meta] is true only when the
/// family came from the file's own metadata, which is what makes a
/// mismatch certain.
List<Map<String, Object>> phoneLoraFacts({
  List<LoraOption> options = const [],
  List<DeskLoraCheck> checks = const [],
}) {
  return [
    for (final row in options)
      {
        'file': row.name,
        'family': row.family.name,
        'meta': row.familyFromMetadata,
      },
    for (final row in checks)
      {'file': row.file, 'family': row.family.name, 'meta': row.metadataBacked},
  ];
}
