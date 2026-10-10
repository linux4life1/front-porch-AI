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

part of 'settings_page.dart';

/// Hardware & GPU block of the Advanced tab: the graphics card and its
/// memory. The GPU/context controls (context window, GPU layers, backend
/// chips) live in settings_page.gpu.dart. There is no memory estimate here:
/// the Local model card (and the preset editor) work it out exactly, and a
/// second, rougher figure here disagreed with it.
extension _SettingsHardware on _SettingsPageState {
  Widget _buildHardwareGpuSection(
    BuildContext context,
    StorageService storageService,
    HardwareService hardwareService,
    LLMProvider llmProvider,
    bool isPresetActive,
  ) {
    // The box shows what is saved: a preset, the Local model card and the
    // phone change the context without it. What is typed in it is saved as it
    // is typed, so only a different number is put in.
    final saved = storageService.backendSettings.contextSize;
    if (saved != _savedContext) {
      _savedContext = saved;
      if (int.tryParse(_contextSizeController.text) != saved) {
        _contextSizeController.text = saved.toString();
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Hardware & GPU'),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: hardwareService.isDetecting
              ? const Center(child: CircularProgressIndicator())
              : hardwareService.hardwareInfo == null
              ? Text(
                  'Hardware not detected.',
                  style: TextStyle(color: AppColors.negativeAccentOf(context)),
                )
              : _buildHardwareCard(
                  context,
                  hardwareService.hardwareInfo!,
                  llmProvider,
                ),
        ),
        const SizedBox(height: 16),
        _buildGpuControls(
          context,
          storageService,
          hardwareService,
          isPresetActive,
        ),
      ],
    );
  }

  /// The card's name and memory. With KoboldCpp, where the model will run
  /// here, it says where the memory estimate is: on the Local model card,
  /// which an Intel Mac does not have.
  Widget _buildHardwareCard(
    BuildContext context,
    HardwareInfo hw,
    LLMProvider llmProvider,
  ) {
    final local =
        llmProvider.isLocal &&
        !Provider.of<BackendManager>(context, listen: false).isIntelMac;
    final faint = AppColors.textTertiary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.memory,
              color: AppColors.porchAmberOf(context),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hw.gpuName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 30, top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hw.vramMb <= 0
                    ? '$kGraphicsMemoryUnknown.'
                    : '${koboldMemoryWords(hw.vramMb)} of graphics memory'
                          '${hw.isSharedMemory ? ', shared with the system' : ''}.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context),
                ),
              ),
              if (local) ...[
                const SizedBox(height: 8),
                Text(
                  'The Local model card, on the Backend tab, shows how your '
                  'model and its chat fit in this memory.',
                  style: TextStyle(fontSize: 12, color: faint, height: 1.4),
                ),
              ] else if (!llmProvider.isLocal) ...[
                const SizedBox(height: 8),
                Text(
                  'Remote API — GPU not in use',
                  style: TextStyle(fontSize: 12, color: faint),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
