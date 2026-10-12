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

import 'package:front_porch_ai/services/kobold_speed_test.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_provider/managed_kobold_launcher.dart';
import 'package:front_porch_ai/services/llm_provider/story_lane_hosts.dart';
import 'package:front_porch_ai/services/llm_provider/worker_lane_swap.dart';

/// What a constructed [LLMProvider] owns that [LLMProviderLaneApi] reads.
/// The provider's constructor registers it. A test double that implements
/// the provider has none, and the API then answers as a provider with no
/// GPU swap, no refused start and no speed test does.
class LlmProviderParts {
  LlmProviderParts({required this.lane, required this.launcher});

  final WorkerLaneSwap lane;
  final ManagedKoboldLauncher launcher;

  /// Made last, once the provider is wired.
  KoboldSpeedTest? speedTest;

  static final Expando<LlmProviderParts> _byProvider = Expando(
    'fpai.llmProviderParts',
  );

  static LlmProviderParts? of(LLMProvider provider) => _byProvider[provider];

  void attachTo(LLMProvider provider) => _byProvider[provider] = this;
}

/// The worker-lane, connection-hint, speed-test and lane-label surface that
/// chat, settings and the web relay call on any [LLMProvider], including the
/// golden doubles that implement it without these members.
extension LLMProviderLaneApi on LLMProvider {
  LlmProviderParts? get _parts => LlmProviderParts.of(this);

  /// Dual-local unload/swap is available for this pair. Widget tests
  /// stay fail-closed unless they inject [LLMProvider.debugGpuSwap].
  bool get workerGpuSwapAvailable => _parts?.lane.available ?? false;

  Future<T> withWorkerLane<T>(Future<T> Function() work) =>
      _parts?.lane.withLane(work) ?? work();

  Future<void> openWorkerLane() => _parts?.lane.open() ?? Future<void>.value();

  Future<void> closeWorkerLane() =>
      _parts?.lane.close() ?? Future<void>.value();

  bool get isWorkerLaneHeld => _parts?.lane.isHeld ?? false;

  bool get gpuSwapBusy => _parts?.lane.isBusy ?? false;

  /// Auto-ping may open the worker only after an explicit handoff
  /// (worker resident). Mouth-up / mid-swap must not start prepare-worker.
  bool get workerLaneReadyForAutoPing => _parts?.lane.readyForAutoPing ?? true;

  Future<void> waitForWorkerLaneIdle({bool pinSpeech = false}) =>
      _parts?.lane.waitForIdle(pinSpeech: pinSpeech) ?? Future<void>.value();

  /// Release the speech pin so post-eval hold may unload the mouth.
  void endMouthSpeech() => _parts?.lane.endMouthSpeech();

  /// In place of "No API connection": why the app's start of KoboldCpp was
  /// refused, in plain words. Null while it runs or starts, and once what the
  /// engine has loaded has changed since the refusal.
  String? get composerConnectionHint {
    if (!hasManagedProcess || composerConnectionReady) return null;
    return _parts?.launcher.refusalHint;
  }

  /// The speed test, one for the app: the desktop's card and the phone's
  /// both run and follow this one. Made with the provider; null on a test
  /// double that stands in for it, which has none.
  KoboldSpeedTest? get koboldSpeedTest => _parts?.speedTest;

  /// "KoboldCpp · Qwen3", "OpenRouter · Opus": what a lane runs on and which
  /// model, or null when it has none. Builds no host, so a screen can ask on
  /// every frame.
  String? laneLabel({
    required String type,
    required String url,
    required String model,
  }) => storyLaneHostLabel(
    type: type,
    url: url,
    model: model,
    koboldLaunchPath: (m) {
      final raw = m.trim();
      if (raw.isNotEmpty && raw != 'kobold') return raw;
      return _parts?.launcher.effectiveLaunchPath(m) ?? '';
    },
  );
}
