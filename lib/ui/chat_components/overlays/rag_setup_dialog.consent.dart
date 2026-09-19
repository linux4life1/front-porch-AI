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

part of 'rag_setup_dialog.dart';

extension _RagSetupConsent on RagSetupDialogState {
  Widget _buildConsentView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.purpleAccent, Colors.deepPurple],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.psychology,
                color: AppColors.textPrimary(context),
                size: 22,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Enable Memory (RAG)',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),

        // Explanation
        Text(
          'Memory (RAG) gives your AI the ability to recall past conversations — even ones that have left the context window.',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
            height: 1.5,
          ),
        ),
        SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.borderOf(context).withValues(alpha: 0.12),
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(
                icon: Icons.download,
                color: AppColors.formMasterAccent,
                text: 'Downloads a ~550 MB AI embedding model on first setup',
              ),
              SizedBox(height: 8),
              InfoRow(
                icon: Icons.memory,
                color: Colors.tealAccent,
                text:
                    'Runs inside the app on your CPU — no data leaves your machine',
              ),
              SizedBox(height: 8),
              InfoRow(
                icon: Icons.search,
                color: Colors.purpleAccent,
                text:
                    'Searches past messages for relevant context to include in prompts',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.textTertiary(context)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () {
                rebuildState(() => _isSettingUp = true);
                _startSetup();
              },
              icon: Icon(Icons.rocket_launch, size: 16),
              label: Text('Set Up & Enable'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: AppColors.textPrimary(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
