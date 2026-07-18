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

/// Per-stage sampling profiles for the Porch Stories pipeline.
///
/// Users never see these — stories deliberately expose no sampler dials, so
/// the pipeline has to pick well on its own. Before this table every stage
/// shared one sampler set (topP 0.9 / minP 0.05 / repPen 1.1) and mostly one
/// temperature, which sampled a strict-JSON planning call and a creative
/// prose call nearly identically. The profiles encode what each kind of stage
/// actually wants:
///
/// - Structured planning (act structure, scenes, beats, validation, archivist
///   fact extraction) runs cold: local models keep their JSON intact and the
///   plan stays internally consistent. Low repeat penalty because JSON keys
///   legitimately repeat.
/// - The story bible is creative planning — warm enough that concepts don't
///   come out generic, still disciplined enough to hold its JSON shape.
/// - Prose drafting runs hot with a higher minP floor (keeps small local
///   models coherent at high temperature) and the strongest repeat penalty
///   (long-form prose is where loops actually hurt).
/// - The editor pass sits between: it must improve the draft without
///   rewriting it into something new.
/// - Chat distillation is factual extraction; the merge of distilled chunks
///   is stricter still (pure dedup/reorder, zero invention wanted).
class StoryStageParams {
  final double temperature;
  final double topP;
  final double minP;
  final double repeatPenalty;

  const StoryStageParams({
    required this.temperature,
    required this.topP,
    required this.minP,
    required this.repeatPenalty,
  });

  /// Strict structured planning: act structurer, scene weaver, beat director,
  /// beat validator, archivist.
  static const planning = StoryStageParams(
    temperature: 0.35,
    topP: 0.9,
    minP: 0.05,
    repeatPenalty: 1.05,
  );

  /// Story Architect (concept → bible): creative planning.
  static const bible = StoryStageParams(
    temperature: 0.7,
    topP: 0.92,
    minP: 0.05,
    repeatPenalty: 1.05,
  );

  /// Prose drafting (beat drafter, scene regeneration).
  static const prose = StoryStageParams(
    temperature: 0.85,
    topP: 0.95,
    minP: 0.08,
    repeatPenalty: 1.1,
  );

  /// Editor pass over a drafted beat.
  static const editing = StoryStageParams(
    temperature: 0.6,
    topP: 0.92,
    minP: 0.06,
    repeatPenalty: 1.08,
  );

  /// Chat Distiller chunk pass (messages → event timeline).
  static const distill = StoryStageParams(
    temperature: 0.3,
    topP: 0.9,
    minP: 0.05,
    repeatPenalty: 1.05,
  );

  /// Chat Distiller merge pass (dedup + reorder chunk timelines).
  static const distillMerge = StoryStageParams(
    temperature: 0.2,
    topP: 0.9,
    minP: 0.05,
    repeatPenalty: 1.05,
  );
}
