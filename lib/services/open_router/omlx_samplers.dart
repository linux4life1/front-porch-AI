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

import 'package:front_porch_ai/services/llm_service.dart';

/// The address the oMLX backend is always reached at (LLMProvider points
/// the mouth here; oMLX never reads the Remote API URL).
const String kOmlxApiUrl = 'http://localhost:8000/v1';

/// Whether [apiUrl] is the oMLX backend's own address.
bool isOmlxApiUrl(String apiUrl) {
  final u = apiUrl.trim();
  return (u.endsWith('/') ? u.substring(0, u.length - 1) : u) == kOmlxApiUrl;
}

/// Shortest and longest verbatim run (tokens) the oMLX repeat block allows,
/// across the DRY Strength range.
const int kOmlxNoRepeatNgramMin = 12;
const int kOmlxNoRepeatNgramMax = 32;

/// The oMLX request fields for the settings only oMLX (of the
/// OpenAI-compatible hosts) reads: XTC, sent while its probability is above
/// 0 (oMLX's own default is off), and the two repetition settings below.
///
/// oMLX's repetition penalty looks back only 20 tokens unless told
/// otherwise, so a copy loop whose unit is a whole paragraph never meets its
/// own penalty. [GenerationParams.repPenTokens] (Repeat Penalty Tokens) becomes
/// `repetition_context_size`, the same look-back KoboldCpp's `rep_pen_range`
/// gives.
///
/// oMLX has no DRY. Its nearest tool is `no_repeat_ngram_size`, a hard ban
/// on repeating any run of that many tokens already in the prompt or reply
/// (ngram_window 0 = the whole context). DRY Strength picks the run length:
/// 0.8 (the usual dose) allows 20 tokens, stronger allows fewer. The floor
/// keeps names and short stock phrases free, since unlike DRY the ban has
/// no sequence breakers.
Map<String, Object> omlxSamplerFields(GenerationParams params) => {
  if (params.xtcProbability > 0) ...{
    'xtc_probability': params.xtcProbability,
    'xtc_threshold': params.xtcThreshold,
  },
  if (params.repPenTokens > 0) 'repetition_context_size': params.repPenTokens,
  if (params.dryMultiplier > 0)
    'no_repeat_ngram_size': omlxNoRepeatNgramSize(params.dryMultiplier),
};

/// The `no_repeat_ngram_size` for a DRY Strength above 0.
int omlxNoRepeatNgramSize(double dryMultiplier) => (16 / dryMultiplier)
    .clamp(kOmlxNoRepeatNgramMin.toDouble(), kOmlxNoRepeatNgramMax.toDouble())
    .round();
