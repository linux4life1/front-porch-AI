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

/// Said wherever the context cannot be changed because a preset sets it,
/// on the desktop and on the phone.
const String kPresetOwnsContext =
    'Context size is controlled by the active .kcpps preset and cannot be '
    'edited here.';

/// Whether the chosen preset sets chat's context: KoboldCpp is the backend
/// ([backend], as stored: anything but `openRouter` and `omlx` is KoboldCpp)
/// and a preset is chosen ([kcppsPath]). The one rule for every place the
/// context can be changed. On another backend a preset left chosen is not
/// read, so the context is the user's.
bool koboldPresetOwnsContext({
  required String backend,
  required String? kcppsPath,
}) =>
    backend != 'openRouter' &&
    backend != 'omlx' &&
    (kcppsPath?.trim().isNotEmpty ?? false);
