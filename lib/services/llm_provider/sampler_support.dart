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

import 'package:front_porch_ai/services/llm_provider/backend_type.dart';
import 'package:front_porch_ai/services/open_router/open_router.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';

/// A generation setting that not every backend receives. Temperature,
/// Top-P, Max Output Tokens and Context Size reach every backend (context
/// is the app's own prompt budget), so they are always shown.
enum SamplerKnob {
  minP,
  topK,
  repeatPenalty,
  repeatPenaltyTokens,
  xtc,
  dry,
  dynamicTemp,
  bannedPhrases,
}

/// The settings a reply request to this backend actually carries, so the
/// desktop and the phone show only those. A hidden setting keeps its saved
/// value; switching back brings it back.
///
/// This is a statement about the payload builders (openai_chat_stream.dart
/// for KoboldCpp, open_router_chat_payload.dart for the rest);
/// test/services/sampler_support_test.dart drives both and fails when this
/// table and the wire disagree.
Set<SamplerKnob> samplerKnobsFor(
  BackendType backend, {
  required String remoteApiUrl,
}) => switch (backend) {
  BackendType.kobold => SamplerKnob.values.toSet(),
  BackendType.omlx => _omlxKnobs,
  BackendType.openRouter => remoteSamplerKnobs(remoteApiUrl),
};

/// [samplerKnobsFor] for an OpenAI-compatible host at [apiUrl].
Set<SamplerKnob> remoteSamplerKnobs(String apiUrl) {
  if (isOmlxApiUrl(apiUrl)) return _omlxKnobs;
  if (remoteApiUrlIsXai(apiUrl)) return const {};
  // Repeat Penalty arrives as an approximated frequency_penalty.
  if (remoteApiUrlIsStrictOpenAi(apiUrl)) {
    return const {SamplerKnob.repeatPenalty};
  }
  // Sent to every other host. A routed provider may still ignore them; the
  // app cannot know which do, so they stay.
  return const {SamplerKnob.minP, SamplerKnob.topK, SamplerKnob.repeatPenalty};
}

const _omlxKnobs = {
  SamplerKnob.minP,
  SamplerKnob.topK,
  SamplerKnob.repeatPenalty,
  SamplerKnob.repeatPenaltyTokens,
  SamplerKnob.xtc,
  SamplerKnob.dry,
};
