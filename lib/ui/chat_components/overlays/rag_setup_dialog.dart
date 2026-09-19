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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

part 'rag_setup_dialog.consent.dart';
part 'rag_setup_dialog.setup.dart';

class RagSetupDialog extends StatefulWidget {
  const RagSetupDialog({super.key});

  @override
  State<RagSetupDialog> createState() => RagSetupDialogState();
}

class RagSetupDialogState extends State<RagSetupDialog> {
  bool _isSettingUp = false;
  bool _isDone = false;

  /// Class door for the consent/setup part extensions — [setState] is
  /// @protected and cannot be called from an extension.
  void rebuildState(VoidCallback fn) => setState(fn);

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
              ? _buildSetupView(embeddings)
              : _buildConsentView(),
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

/// Small helper widget for the consent dialog info rows.
class InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const InfoRow({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
