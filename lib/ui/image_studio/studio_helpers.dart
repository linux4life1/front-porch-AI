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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:front_porch_ai/services/services.dart';

/// Pure helpers extracted from the ImageStudio coordinator to keep the main file
/// under the project 500 LOC cap while preserving behavior and readability.
/// These are stateless and test-friendly.

String getAcceptLabel(ImageGenMode mode) {
  switch (mode) {
    case ImageGenMode.characterPortrait:
    case ImageGenMode.userAvatar:
      return 'Set as Avatar';
    case ImageGenMode.customPrompt:
      return '';
  }
}

bool hasAcceptAction(ImageGenMode mode) {
  return mode == ImageGenMode.characterPortrait ||
      mode == ImageGenMode.userAvatar;
}
