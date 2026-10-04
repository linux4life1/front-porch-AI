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

part of 'llm_provider.dart';

/// A story job's own model: the service to call, how to hold the GPU while
/// it runs (local engines swap the model in), and how to put the chat model
/// back afterwards. Remote hosts need no hold; [restore] is a no-op there.
class LaneHost {
  const LaneHost({
    required this.id,
    required this.service,
    required this.hold,
    required this.restore,
    required this.label,
  });

  /// Backend, address, model and preset. Two hosts with the same id are the
  /// same resident model, however many times the host was built.
  final String id;
  final LLMService service;
  final Future<T> Function<T>(Future<T> Function() work) hold;
  final Future<void> Function() restore;
  final String label;
}

/// The chat model lives on a remote API: nothing to unload or restore.
class _RemoteMouthHost implements GpuSwapHost {
  const _RemoteMouthHost();
  @override
  String get label => 'remote chat model';
  @override
  Future<void> unload() => Future<void>.value();
  @override
  Future<void> restore() => Future<void>.value();
}

final Expando<Map<String, OpenRouterService>> _laneRemotes =
    Expando<Map<String, OpenRouterService>>('fpai.laneRemotes');
final Expando<Map<String, GpuSwapOccupancy>> _laneSwaps =
    Expando<Map<String, GpuSwapOccupancy>>('fpai.laneSwaps');

/// Per-lane hosts for Porch Stories: any host + model for any job, on the
/// same unload / load swap the chat ↔ worker pair uses.
extension LLMProviderLanes on LLMProvider {
  /// The host for a story lane, or null when it cannot be built (no model).
  LaneHost? laneHost({
    required String type,
    required String url,
    required String model,
    String kcpps = '',
  }) {
    final t = type.trim();
    final isKobold = t == 'kobold';
    final laneModel = isKobold
        ? _effectiveKoboldLaunchPath(model)
        : model.trim();
    if (laneModel.isEmpty) return null;

    final resolvedUrl = t == 'omlx' ? kOmlxApiV1 : resolvedLaneApiUrl(t, url);
    final key = isKobold ? '' : _storageService.remoteApiKeyFor(resolvedUrl);
    final id = '$t|$resolvedUrl|$laneModel|$kcpps';

    final LLMService service;
    if (isKobold) {
      service = _koboldService;
    } else {
      final remotes = _laneRemotes[this] ??= {};
      service = remotes.putIfAbsent(
        id,
        () => OpenRouterService(
          apiUrl: resolvedUrl,
          apiKey: key,
          modelName: laneModel,
        ),
      )..configure(apiKey: key);
    }
    final label = isKobold
        ? 'KoboldCpp · ${storyShortModelName(laneModel)}'
        : '${remoteProviderLabel(t, resolvedUrl)} · ${storyShortModelName(laneModel)}';

    if (localSwapKindFor(backendType: t, apiUrl: url) == null) {
      return LaneHost(
        id: id,
        service: service,
        hold: <T>(work) => work(),
        restore: () => Future<void>.value(),
        label: label,
      );
    }

    final mouthType = _storageService.backendSettings.backendType;
    final mouthUrl = _storageService.backendSettings.remoteApiUrl;
    final mouthModel = _mouthSwapModelId();
    final mouthKcpps = _koboldKcppsId(worker: false);
    final same = workerLanesShareResident(
      mouthType: mouthType,
      mouthUrl: mouthUrl,
      mouthModel: mouthModel,
      workerType: t,
      workerUrl: url,
      workerModel: laneModel,
      mouthKcpps: mouthKcpps,
      workerKcpps: kcpps,
    );
    final swaps = _laneSwaps[this] ??= {};
    final occupancy = swaps.putIfAbsent(id, () {
      final mouth =
          _hostForLane(
            role: kKoboldChatRole,
            type: mouthType,
            url: mouthUrl,
            model: mouthModel,
            kcpps: mouthKcpps,
            key: _storageService.remoteApiKeyFor(
              resolvedLaneApiUrl(mouthType, mouthUrl),
            ),
          ) ??
          const _RemoteMouthHost();
      final lane = _hostForLane(
        // One staged file per job, named from what the job runs on.
        role: 'lane-${id.hashCode.toUnsigned(32).toRadixString(16)}',
        type: t,
        url: url,
        model: laneModel,
        kcpps: kcpps,
        key: key,
      )!;
      return GpuSwapOccupancy(
        mouth: mouth,
        worker: lane,
        sameResident: same,
        sharedEngine: mouth is KoboldProcessHost && lane is KoboldProcessHost,
        // The lane's calls go to the one KoboldCpp process: only trust
        // "my model is loaded" while nothing else has reloaded it.
        residentGeneration: lane is KoboldProcessHost
            ? () => _koboldService.loadGeneration
            : null,
      );
    });
    return LaneHost(
      id: id,
      service: service,
      hold: occupancy.hold,
      restore: occupancy.ensureMouth,
      label: label,
    );
  }
}

/// "OpenRouter", "LM Studio", "oMLX", "Custom"… for a lane label.
String remoteProviderLabel(String type, String resolvedUrl) {
  if (type == 'omlx') return 'oMLX';
  final kind = resolveRemoteProviderKind(backendType: type, url: resolvedUrl);
  return remoteProviderKindLabel(kind);
}
