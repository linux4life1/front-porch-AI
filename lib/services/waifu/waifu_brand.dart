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

/// User-facing product name. Internal types, files, keys, and routes use
/// `Waifu*` / `waifu_*` too, so the product has one name at every layer.
const kWaifuCoderName = 'Waifu Coder';

/// New skills, workflows, inbox photos, and language data write here.
const kWaifuDotDir = '.waifu';

/// Legacy on-disk folder only. Read for migration; never used for new writes.
const kWaifuLegacyDotDir = '.desk';
