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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/ui/desk/desk_work_strip.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Desk session. Send runs the in-process tool loop. No Continue, no regen.
class DeskPage extends StatefulWidget {
  const DeskPage({super.key, required this.session, this.harness, this.llm});

  final DeskSession session;
  final DeskHarness? harness;
  final DeskLlm? llm;

  @override
  State<DeskPage> createState() => _DeskPageState();
}

class _DeskPageState extends State<DeskPage> {
  final _composer = TextEditingController();
  DeskHarness? _created;

  @override
  void initState() {
    super.initState();
    widget.harness?.onChanged = _refresh;
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  DeskHarness? _harnessOf(BuildContext context) {
    final injected = widget.harness;
    if (injected != null) return injected;
    if (_created != null) return _created;
    final llm = widget.llm;
    if (llm != null) {
      return _created = DeskHarness(
        session: widget.session,
        llm: llm,
        onChanged: _refresh,
      );
    }
    try {
      final provider = Provider.of<LLMProvider>(context, listen: false);
      return _created = DeskHarness(
        session: widget.session,
        llm: LlmServiceDeskLlm(provider.activeService),
        onChanged: _refresh,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final harness = _harnessOf(context);
    if (harness == null) {
      setState(() {
        widget.session.transcript.add(DeskMessage(isUser: true, text: text));
        _composer.clear();
      });
      return;
    }
    _composer.clear();
    await harness.send(text);
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
          Expanded(child: _transcript(session, amber)),
          if (session.lastWrite != null)
            DeskWorkStrip(record: session.lastWrite!),
          _composerRow(session, amber),
        ],
      ),
    );
  }

  Widget _transcript(DeskSession session, Color amber) {
    if (session.transcript.isEmpty) {
      return Center(
        child: Text(
          'Tell her what to do. She will loop tools in this folder.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: session.transcript.length,
      itemBuilder: (context, i) {
        final msg = session.transcript[i];
        return Align(
          alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: msg.isUser
                  ? amber.withValues(alpha: 0.2)
                  : AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (msg.text.isNotEmpty)
                  Text(
                    msg.text,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                if (msg.chips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final chip in msg.chips)
                        Text(
                          '${chip.name} ${chip.detail}',
                          style: TextStyle(
                            fontSize: 11,
                            color: chip.ok
                                ? amber
                                : AppColors.textSecondary(context),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _composerRow(DeskSession session, Color amber) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('desk-composer'),
              controller: _composer,
              enabled: !session.running,
              decoration: InputDecoration(
                hintText: 'A task for ${session.coworker.name}',
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.borderOf(context)),
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          if (session.running)
            IconButton(
              key: const Key('desk-abort'),
              onPressed: () => _harnessOf(context)?.abort(),
              icon: Icon(Icons.stop_circle, color: amber),
              tooltip: 'Abort',
            )
          else
            IconButton(
              key: const Key('desk-send'),
              onPressed: _send,
              icon: Icon(Icons.send, color: amber),
            ),
        ],
      ),
    );
  }
}
