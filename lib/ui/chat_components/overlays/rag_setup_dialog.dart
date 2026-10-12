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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'rag_setup/rag_setup.dart';

export 'rag_setup/info_row.dart' show InfoRow;

class RagSetupDialog extends StatefulWidget {
  const RagSetupDialog({super.key});

  @override
  State<RagSetupDialog> createState() => RagSetupDialogState();
}

class RagSetupDialogState extends State<RagSetupDialog> {
  bool _isSettingUp = false;
  bool _isDone = false;

  @override
  Widget build(BuildContext context) {
    final embeddings = Provider.of<EmbeddingService>(context);

    return Dialog(
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isSettingUp
              ? RagSetupProgressView(
                  embeddings: embeddings,
                  isDone: _isDone,
                  onRetry: _startSetup,
                )
              : RagConsentView(
                  onStartSetup: () {
                    setState(() => _isSettingUp = true);
                    _startSetup();
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _startSetup() async {
    final embeddings = Provider.of<EmbeddingService>(context, listen: false);

    // Downloads the model if needed, then loads + self-tests the engine.
    final ready = await embeddings.runSetup();
    if (!mounted) return;

    if (ready) {
      setState(() => _isDone = true);
    }
    // If not ready, the error state shows via embeddings.setupError.
  }
}
