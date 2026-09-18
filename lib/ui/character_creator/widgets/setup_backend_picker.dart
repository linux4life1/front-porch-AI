// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/backend_chip.dart';
import 'package:front_porch_ai/ui/settings/widgets/remote_provider_apply.dart';
import 'package:front_porch_ai/ui/settings/widgets/remote_provider_bar.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Kobold / Remote API / oMLX chips, plus OpenRouter vs Nano-GPT vs LM Studio
/// when the remote door is open. Shared by AI Character Creator and World
/// from Wiki (same Setup step).
class SetupBackendPicker extends StatelessWidget {
  const SetupBackendPicker({super.key, required this.state});

  final CreatorState state;

  @override
  Widget build(BuildContext context) {
    final llmProvider = Provider.of<LLMProvider>(context);
    final storage = Provider.of<StorageService>(context);
    final activeBackend = llmProvider.activeBackend;
    final isKobold = activeBackend == BackendType.kobold;
    final isRemote = activeBackend == BackendType.openRouter;
    final isAppleSiliconMac =
        Platform.isMacOS && Abi.current() == Abi.macosArm64;
    final remoteKind = resolveRemoteProviderKind(
      backendType: storage.backendSettings.backendType,
      url: storage.backendSettings.remoteApiUrl,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _inputLabel(context, 'Backend'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: BackendChip(
                label: 'KoboldCpp (Local)',
                icon: Icons.computer,
                isSelected: isKobold,
                onTap: () async {
                  if (!isKobold) {
                    await llmProvider.setActiveBackend(BackendType.kobold);
                    state.scanLocalModels(storage);
                    state.scanLocalPresets(storage);
                    state.notify();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BackendChip(
                label: 'API (Remote)',
                icon: Icons.cloud,
                isSelected: isRemote,
                onTap: () async {
                  if (!isRemote) {
                    await llmProvider.setActiveBackend(BackendType.openRouter);
                  }
                  await state.loadAvailableModels(llmProvider);
                  state.notify();
                },
              ),
            ),
            if (isAppleSiliconMac) ...[
              const SizedBox(width: 8),
              Expanded(
                child: BackendChip(
                  label: 'oMLX',
                  icon: Icons.apple,
                  isSelected: activeBackend == BackendType.omlx,
                  onTap: () async {
                    if (activeBackend != BackendType.omlx) {
                      await llmProvider.setActiveBackend(BackendType.omlx);
                      await state.loadAvailableModels(llmProvider);
                    }
                  },
                ),
              ),
            ],
          ],
        ),
        if (isRemote) ...[
          const SizedBox(height: 16),
          _inputLabel(context, 'Provider'),
          const SizedBox(height: 8),
          RemoteProviderBar(
            selected: remoteKind,
            remoteHostsOnly: true,
            onSelected: (next) async {
              await applyRemoteProvider(
                kind: next,
                storage: storage,
                llm: llmProvider,
              );
              state.selectedModelId = storage.backendSettings.remoteModelName;
              await state.loadAvailableModels(llmProvider);
              state.notify();
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Each provider keeps its own key and last model.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _inputLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: AppColors.textSecondary(context),
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
