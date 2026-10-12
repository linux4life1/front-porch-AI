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

/// How the pre-generation realism judges are fused (eval review Tier-1 §3.4,
/// maintainer-approved 2026-08-10). [auto] — the default — uses the fused
/// one-shot call on remote backends that have already proven native tool
/// calls (exactly the class of model the combined prompt is easy for) and the
/// multi-call path everywhere else, including every local backend. [on]/[off]
/// are the explicit choices the old bool expressed; the user always wins in
/// both directions.
enum OneShotMode { auto, on, off }
