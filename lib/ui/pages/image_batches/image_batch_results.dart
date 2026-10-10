// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

class ImageBatchResults extends StatelessWidget {
  const ImageBatchResults({
    super.key,
    required this.queue,
    required this.review,
    required this.onAction,
  });
  final ImageBatchService queue;
  final bool review;
  final Future<void> Function(Future<void> Function()) onAction;
  @override
  Widget build(BuildContext context) {
    final rows = queue.jobs
        .where(
          (j) => review
              ? ['review', 'saved', 'failed', 'interrupted'].contains(j.state)
              : j.state != 'discarded',
        )
        .toList();
    if (rows.isEmpty) {
      return Center(
        child: Text(
          review
              ? 'Finished images will appear here for review.'
              : 'Prepare a batch to add images to the queue.',
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final job = rows[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${job.characterName} · ${job.label} · ${job.state}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (review && job.data['candidate'] != null)
                  FutureBuilder<Uint8List>(
                    future: queue.picture(job.id),
                    builder: (context, image) => image.hasData
                        ? Image.memory(
                            image.data!,
                            height: 220,
                            fit: BoxFit.contain,
                            semanticLabel:
                                '${job.characterName} ${job.label} candidate',
                          )
                        : Text(
                            image.hasError
                                ? 'Could not load candidate: ${image.error}'
                                : 'Loading candidate…',
                          ),
                  ),
                SelectableText(job.prompt),
                Text(
                  'Seed ${job.data['seed']} · ${job.edit ? 'Edit' : 'Create'} · ${job.data['size']}',
                ),
                if (job.data['error'] != null) Text('${job.data['error']}'),
                Wrap(
                  spacing: 8,
                  children: [
                    if (job.state == 'review')
                      TextButton(
                        onPressed: queue.working
                            ? null
                            : () =>
                                  onAction(() => queue.decide(job.id, 'keep')),
                        child: Text(job.kept ? 'Kept ✓' : 'Keep'),
                      ),
                    if ([
                      'review',
                      'saved',
                      'failed',
                      'interrupted',
                    ].contains(job.state))
                      TextButton(
                        onPressed: queue.working
                            ? null
                            : () async {
                                final controller = TextEditingController(
                                  text: job.prompt,
                                );
                                bool newSeed = true;
                                final chosen = await showWarmDialogOf<bool>(
                                  context,
                                  builder: (context) => StatefulBuilder(
                                    builder: (context, update) => WarmDialog(
                                      title: 'Prepare another pass',
                                      width: 560,
                                      content: SizedBox(
                                        width: 520,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextField(
                                              controller: controller,
                                              minLines: 3,
                                              maxLines: 6,
                                              decoration: const InputDecoration(
                                                labelText: 'Prompt',
                                              ),
                                            ),
                                            CheckboxListTile(
                                              value: newSeed,
                                              onChanged: (v) =>
                                                  update(() => newSeed = v!),
                                              title: const Text(
                                                'Use a new seed',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Add to queue'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                                if (chosen == true) {
                                  await onAction(
                                    () => queue.decide(
                                      job.id,
                                      'redo',
                                      prompt: controller.text,
                                      newSeed: newSeed,
                                    ),
                                  );
                                }
                                controller.dispose();
                              },
                        child: const Text('Redo…'),
                      ),
                    if ([
                      'waiting',
                      'review',
                      'failed',
                      'interrupted',
                    ].contains(job.state))
                      TextButton(
                        onPressed: queue.working
                            ? null
                            : () => onAction(
                                () => queue.decide(job.id, 'discard'),
                              ),
                        child: const Text('Discard'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
