// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/image/image.dart';

class ImageBatchCandidatePicture extends StatefulWidget {
  const ImageBatchCandidatePicture({
    super.key,
    required this.queue,
    required this.job,
  });
  final ImageBatchService queue;
  final ImageBatchJob job;
  @override
  State<ImageBatchCandidatePicture> createState() =>
      _ImageBatchCandidatePictureState();
}

class _ImageBatchCandidatePictureState
    extends State<ImageBatchCandidatePicture> {
  late Future<Uint8List> _picture;
  @override
  void initState() {
    super.initState();
    _picture = widget.queue.picture(widget.job.id);
  }

  @override
  void didUpdateWidget(ImageBatchCandidatePicture old) {
    super.didUpdateWidget(old);
    if (old.queue != widget.queue ||
        old.job.id != widget.job.id ||
        old.job.data['candidate'] != widget.job.data['candidate']) {
      _picture = widget.queue.picture(widget.job.id);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _picture,
    builder: (context, image) => image.hasData
        ? Image.memory(
            image.data!,
            height: 220,
            fit: BoxFit.contain,
            semanticLabel:
                '${widget.job.characterName} ${widget.job.label} candidate',
          )
        : Text(
            image.hasError ? 'Could not load candidate.' : 'Loading candidate…',
          ),
  );
}
