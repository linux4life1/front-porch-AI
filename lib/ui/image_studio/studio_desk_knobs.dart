// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'remote_image_host_chips.dart';
import 'studio_commit_field.dart';

/// Every setting a generate reads that the graph and model controls do not
/// cover, each with a control you can see: the Remote host, seed, negative
/// prompt, the Draw Things cluster (port, shift, seed mode, TeaCache, CFG
/// Zero), the prompt-review switch, and the default style and prompt format.
/// Steps, CFG, sampler and scheduler are the stove's own sliders.
///
/// A knob is shown exactly when its setting can change a generate on the
/// current backend, so nothing applies unseen and nothing is shown that does
/// nothing.
class StudioDeskKnobs extends StatelessWidget {
  const StudioDeskKnobs({
    super.key,
    required this.settings,
    this.edit = false,
    this.comfyShiftGraph,
    this.comfyOwnShift = kEditRecommendedShift,
  });

  final ImageGenSettings settings;
  final bool edit;

  /// The id of the Comfy graph on the desk when it has a sampling-shift node.
  /// Without one the slider would change nothing, so it is not shown.
  final String? comfyShiftGraph;

  /// That graph's own shift, where the slider starts.
  final double comfyOwnShift;

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final backend = settings.imageGenBackend;
    final drawThings = backend == 'drawthings';
    final surface = imageSurfaceFor(
      backend: ImageGenBackend.fromKey(backend),
      modelName: edit ? settings.imageGenEditModel : settings.imageGenModel,
    );
    final primary = AppColors.textPrimary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (backend == 'remote') ...[
          RemoteImageHostChips(
            selectedUrl: settings.imageRemoteApiUrl,
            keyFor: storage.backendSettings.remoteApiKeyFor,
            onSelect: (url) => applyImageRemoteHost(
              image: settings,
              url: url,
              chatRemoteApiUrl: storage.backendSettings.remoteApiUrl,
              editScoped: edit,
            ),
          ),
          const SizedBox(height: 8),
          StudioRemoteKeyNote(settings: settings, storage: storage),
        ],
        if (backend != 'remote')
          StudioCommitField(
            key: ValueKey('seed-${settings.imageGenSeed}'),
            value: '${settings.imageGenSeed}',
            label: 'Seed',
            hint: '-1 = random',
            onSubmit: (value) =>
                settings.setImageGenSeed(int.tryParse(value.trim()) ?? -1),
          ),
        if (surface.showNegative)
          StudioCommitField(
            key: ValueKey('negative-${settings.imageGenNegativePrompt}'),
            value: settings.imageGenNegativePrompt,
            label: 'Negative prompt',
            hint: 'e.g. blurry, extra fingers',
            maxLines: 2,
            onSubmit: settings.setImageGenNegativePrompt,
          ),
        if (backend == 'comfyui' && comfyShiftGraph != null)
          ..._comfyShift(primary, comfyShiftGraph!),
        if (drawThings) ..._drawThings(context, primary),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            'Review AI prompts before generating',
            style: TextStyle(color: primary),
          ),
          subtitle: const Text(
            '/image in chat pauses so you can edit the crafted prompt first.',
          ),
          value: settings.imageGenPromptReview,
          activeTrackColor: AppColors.formMasterAccent,
          onChanged: settings.setImageGenPromptReview,
        ),
        if (!edit)
          ..._promptStyle(context)
        else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Style and Prompt format are in Create mode.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  /// Moving the slider sets Shift for this graph only. Until it is moved the
  /// graph posts its own value, which is where the slider starts.
  List<Widget> _comfyShift(Color primary, String graph) {
    final moved = settings.comfyShiftFor(graph, edit: edit);
    return [
      _shiftRow(
        primary,
        moved ?? comfyOwnShift,
        (value) => settings.setComfyShift(graph, value, edit: edit),
      ),
      if (moved != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => settings.clearComfyShift(graph, edit: edit),
            child: const Text('Use the graph\'s own shift'),
          ),
        ),
    ];
  }

  List<Widget> _drawThings(BuildContext context, Color primary) {
    final shift = edit ? settings.editShift : settings.drawThingsShift;
    final seedMode = edit ? settings.editSeedMode : settings.drawThingsSeedMode;
    return [
      StudioCommitField(
        key: ValueKey('port-${settings.drawThingsGrpcPort}'),
        value: '${settings.drawThingsGrpcPort}',
        label: 'Draw Things port',
        onSubmit: (value) {
          final port = int.tryParse(value.trim());
          if (port != null && port > 0) settings.setDrawThingsGrpcPort(port);
        },
      ),
      _shiftRow(
        primary,
        shift,
        (value) => edit
            ? settings.setEditShift(value)
            : settings.setDrawThingsShift(value),
      ),
      Row(
        children: [
          Text('Seed mode', style: TextStyle(color: primary)),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: seedMode.clamp(0, 3),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Random')),
              DropdownMenuItem(value: 1, child: Text('Constant')),
              DropdownMenuItem(value: 2, child: Text('Per image')),
              DropdownMenuItem(value: 3, child: Text('From prompt')),
            ],
            onChanged: (value) {
              if (value == null) return;
              if (edit) {
                settings.setEditSeedMode(value);
              } else {
                settings.setDrawThingsSeedMode(value);
              }
            },
          ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text('TeaCache', style: TextStyle(color: primary)),
        value: settings.drawThingsTeaCache,
        activeTrackColor: AppColors.formMasterAccent,
        onChanged: settings.setDrawThingsTeaCache,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text('CFG Zero', style: TextStyle(color: primary)),
        value: settings.drawThingsCfgZeroStar,
        activeTrackColor: AppColors.formMasterAccent,
        onChanged: settings.setDrawThingsCfgZeroStar,
      ),
    ];
  }

  /// A shift slider. Comfy keeps one per graph; Draw Things keeps one per mode.
  Widget _shiftRow(
    Color primary,
    double shift,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        Text('Shift', style: TextStyle(color: primary)),
        Expanded(
          child: Slider(
            value: shift.clamp(0.0, 10.0),
            min: 0,
            max: 10,
            divisions: 100,
            label: shift.toStringAsFixed(1),
            activeColor: AppColors.formMasterAccent,
            onChanged: onChanged,
          ),
        ),
        Text(shift.toStringAsFixed(1), style: TextStyle(color: primary)),
      ],
    );
  }

  /// The defaults the prompt writer and chat's /image start from.
  List<Widget> _promptStyle(BuildContext context) {
    final style =
        ImageGenService.styleLabels.containsKey(settings.imageGenStyle)
        ? settings.imageGenStyle
        : 'photorealistic';
    return [
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: ValueKey('style-$style'),
        initialValue: style,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Style'),
        items: [
          for (final entry in ImageGenService.styleLabels.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) {
          if (value != null) settings.setImageGenStyle(value);
        },
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: ValueKey('paradigm-${settings.imageGenPromptParadigm}'),
        initialValue: settings.imageGenPromptParadigm,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Prompt format'),
        items: const [
          DropdownMenuItem(
            value: 'natural',
            child: Text('Natural language (FLUX / SD3)'),
          ),
          DropdownMenuItem(
            value: 'tags',
            child: Text('Danbooru tags (SD 1.5 / anime)'),
          ),
        ],
        onChanged: (value) {
          if (value != null) settings.setImageGenPromptParadigm(value);
        },
      ),
    ];
  }
}

class StudioRemoteKeyNote extends StatelessWidget {
  const StudioRemoteKeyNote({
    super.key,
    required this.settings,
    required this.storage,
  });

  final ImageGenSettings settings;
  final StorageService storage;

  @override
  Widget build(BuildContext context) {
    final account = resolveImageStudioRemoteAccount(
      imageRemoteApiUrl: settings.imageRemoteApiUrl,
      chatRemoteApiUrl: storage.backendSettings.remoteApiUrl,
      keyFor: storage.backendSettings.remoteApiKeyFor,
    );
    if (account.key.isEmpty) {
      return Text(
        'No Remote API key configured for this host. Remote images '
        'use the same API account as chat — nothing runs locally and '
        'nothing is free. Add your provider key under Settings → '
        'Backend → Remote API first; models will list once it\'s set.',
        style: TextStyle(color: AppColors.textPrimary(context), fontSize: 11.5),
      );
    }
    final host = Uri.tryParse(account.url)?.host ?? '';
    return Text(
      'Bills your Remote API account'
      '${host.isEmpty ? '' : ' ($host)'} per image.',
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 11,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
