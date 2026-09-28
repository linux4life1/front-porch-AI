// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image/image_studio_remote.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'remote_image_host_chips.dart';
import 'studio_commit_field.dart';

/// Settings the model search does not cover: remote host, CFG, scheduler,
/// seed, negative prompt, and the Draw Things port cluster.
class StudioDeskKnobs extends StatelessWidget {
  const StudioDeskKnobs({super.key, required this.settings, this.edit = false});

  final ImageGenSettings settings;
  final bool edit;

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final backend = settings.imageGenBackend;
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
        StudioCommitField(
          key: ValueKey(
            'cfg-${edit ? settings.editCfgScale : settings.imageGenCfgScale}',
          ),
          value: '${edit ? settings.editCfgScale : settings.imageGenCfgScale}',
          label: 'CFG',
          onSubmit: (value) {
            final cfg = double.tryParse(value);
            if (cfg == null) return;
            if (edit) {
              settings.setEditCfgScale(cfg);
            } else {
              settings.setImageGenCfgScale(cfg);
            }
          },
        ),
        if (backend != 'drawthings' && !edit)
          StudioCommitField(
            key: ValueKey('scheduler-${settings.imageGenScheduler}'),
            value: settings.imageGenScheduler,
            label: 'Scheduler',
            onSubmit: settings.setImageGenScheduler,
          ),
        StudioCommitField(
          key: ValueKey('seed-${settings.imageGenSeed}'),
          value: '${settings.imageGenSeed}',
          label: 'Seed',
          onSubmit: (value) {
            final seed = int.tryParse(value);
            if (seed != null) settings.setImageGenSeed(seed);
          },
        ),
        StudioCommitField(
          key: ValueKey('negative-${settings.imageGenNegativePrompt}'),
          value: settings.imageGenNegativePrompt,
          label: 'Negative prompt',
          onSubmit: settings.setImageGenNegativePrompt,
        ),
        if (backend == 'drawthings') ...[
          StudioCommitField(
            key: ValueKey('port-${settings.drawThingsGrpcPort}'),
            value: '${settings.drawThingsGrpcPort}',
            label: 'Draw Things port',
            onSubmit: (value) {
              final port = int.tryParse(value);
              if (port != null && port > 0) {
                settings.setDrawThingsGrpcPort(port);
              }
            },
          ),
          StudioCommitField(
            key: ValueKey(
              'shift-${edit ? settings.editShift : settings.drawThingsShift}',
            ),
            value: '${edit ? settings.editShift : settings.drawThingsShift}',
            label: 'Shift',
            onSubmit: (value) {
              final shift = double.tryParse(value);
              if (shift == null) return;
              if (edit) {
                settings.setEditShift(shift);
              } else {
                settings.setDrawThingsShift(shift);
              }
            },
          ),
          StudioCommitField(
            key: ValueKey(
              'seed-mode-${edit ? settings.editSeedMode : settings.drawThingsSeedMode}',
            ),
            value:
                '${edit ? settings.editSeedMode : settings.drawThingsSeedMode}',
            label: 'Seed mode',
            onSubmit: (value) {
              final mode = int.tryParse(value);
              if (mode == null) return;
              if (edit) {
                settings.setEditSeedMode(mode);
              } else {
                settings.setDrawThingsSeedMode(mode);
              }
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'TeaCache',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            value: settings.drawThingsTeaCache,
            activeTrackColor: AppColors.formMasterAccent,
            onChanged: settings.setDrawThingsTeaCache,
          ),
        ],
      ],
    );
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
