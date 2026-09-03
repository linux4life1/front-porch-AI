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

/// How a backend identity accepts OpenAI `tool_choice`.
///
/// Named function objects are the default (scalar evals always want exactly
/// one function). Some older OpenAI-compatible hosts only accept
/// `'auto' | 'none' | 'required'` and 400 a named object. The style probe
/// remembers that 400 so the next call starts on the style that worked.
/// It is NEVER a capability verdict — a host that 400s named choice may
/// still speak tools.
enum ToolChoiceStyle { named, required, auto }

/// Per-identity memory of which `tool_choice` encoding this host accepts.
///
/// Injectable default singleton, same shape as [SystemRoleProbe]: tests
/// construct their own so a static map cannot leak between cases.
class ToolChoiceStyleProbe {
  ToolChoiceStyleProbe();

  /// App-wide default. Kobold / OpenRouter doors read this unless a test
  /// injected its own via [attachToolsWithStyleRetry]'s `probe` argument.
  static final ToolChoiceStyleProbe instance = ToolChoiceStyleProbe();

  final Map<String, ToolChoiceStyle> _style = {};

  ToolChoiceStyle styleFor(String identity) =>
      _style[identity] ?? ToolChoiceStyle.named;

  void remember(String identity, ToolChoiceStyle style) =>
      _style[identity] = style;

  void reset(String identity) => _style.remove(identity);

  @visibleForTesting
  void resetForTest() => _style.clear();
}
