// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// "Change…": picks which kind of image server the studio talks to.
class StudioBackendMenu extends StatelessWidget {
  const StudioBackendMenu({
    super.key,
    required this.backend,
    required this.onBackend,
  });

  final String backend;
  final ValueChanged<String> onBackend;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onBackend,
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'remote', child: Text('Remote')),
        const PopupMenuItem(value: 'comfyui', child: Text('ComfyUI')),
        const PopupMenuItem(value: 'a1111', child: Text('Automatic1111')),
        if (defaultTargetPlatform == TargetPlatform.macOS ||
            backend == 'drawthings')
          const PopupMenuItem(value: 'drawthings', child: Text('Draw Things')),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text('Change…'),
      ),
    );
  }
}
