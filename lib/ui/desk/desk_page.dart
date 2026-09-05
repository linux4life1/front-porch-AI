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
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Empty Desk session chrome. Slice A has no tool loop — Send only
/// appends the user's line to the in-memory transcript.
class DeskPage extends StatefulWidget {
  const DeskPage({super.key, required this.session});

  final DeskSession session;

  @override
  State<DeskPage> createState() => _DeskPageState();
}

class _DeskPageState extends State<DeskPage> {
  final _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() {
      widget.session.transcript.add(DeskMessage(isUser: true, text: text));
      _composer.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final amber = AppColors.porchAmberOf(context);
    final folderName = p.basename(session.folderRoot);
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.coworker.name),
            Text(
              folderName,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: session.transcript.isEmpty
                ? Center(
                    child: Text(
                      'Tell her what to do. The harness lands in a later slice.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: session.transcript.length,
                    itemBuilder: (context, i) {
                      final msg = session.transcript[i];
                      return Align(
                        alignment: msg.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: msg.isUser
                                ? amber.withValues(alpha: 0.2)
                                : AppColors.cardOf(context),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            msg.text,
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('desk-composer'),
                    controller: _composer,
                    decoration: InputDecoration(
                      hintText: 'A task for ${session.coworker.name}',
                      filled: true,
                      fillColor: AppColors.surfaceContainerOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.borderOf(context),
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('desk-send'),
                  onPressed: _send,
                  icon: Icon(Icons.send, color: amber),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
