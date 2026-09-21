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
/// remembers a named-object 400 as [ToolChoiceStyle.required] so the next
/// call starts there.
///
/// [auto] is **never durable**. Persisting it after a `tool_choice` 400
/// disarmed the next overlay `report_*` judge (the #230 streaming-auto bug
/// coming back after one bad provider 400). A step to `auto` is one-shot
/// for this request only. Journal/Growth pass an empty toolChoice and
/// always send `auto` without reading or writing this map.
///
/// It is NEVER a capability verdict — a host that 400s named choice may
/// still speak tools.
enum ToolChoiceStyle { named, required, auto }

/// [GenerationParams.toolChoice] sentinel: OpenAI `tool_choice: "required"`
/// (any advertised tool), not a named function. Null/empty still means auto.
const kToolChoiceRequired = 'required';

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

  /// Named evals start at [ToolChoiceStyle.named] or a remembered
  /// [ToolChoiceStyle.required]. Leftover [ToolChoiceStyle.auto] in the
  /// map is treated as unset so a prior one-shot cannot disarm later
  /// `report_*` calls.
  ToolChoiceStyle styleFor(String identity) {
    final remembered = _style[identity];
    if (remembered == null || remembered == ToolChoiceStyle.auto) {
      return ToolChoiceStyle.named;
    }
    return remembered;
  }

  /// Journal/Growth (`toolChoice` empty) always send auto. The
  /// [kToolChoiceRequired] sentinel starts at required (any tool). Named
  /// functions use [styleFor] and never start at auto.
  ToolChoiceStyle startingStyleFor(String identity, {String? toolChoice}) {
    if (toolChoice == null || toolChoice.isEmpty) {
      return ToolChoiceStyle.auto;
    }
    if (toolChoice == kToolChoiceRequired) {
      return ToolChoiceStyle.required;
    }
    return styleFor(identity);
  }

  /// Persist named / required only. Auto is ignored so a one-shot
  /// step-down cannot stick across overlay judges.
  void remember(String identity, ToolChoiceStyle style) {
    if (style == ToolChoiceStyle.auto) return;
    _style[identity] = style;
  }

  void reset(String identity) => _style.remove(identity);

  @visibleForTesting
  void resetForTest() => _style.clear();
}
