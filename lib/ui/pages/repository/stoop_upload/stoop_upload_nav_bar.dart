// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';

/// Upload wizard bottom bar: Back (when [showBack]) and Next / Submit.
class StoopUploadNavBar extends StatelessWidget {
  final bool showBack;
  final bool isLast;
  final bool busy;
  final bool canAdvance;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const StoopUploadNavBar({
    super.key,
    required this.showBack,
    required this.isLast,
    required this.busy,
    required this.canAdvance,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: stoopBg0(context),
          border: Border(top: BorderSide(color: stoopBorder(context))),
        ),
        child: Row(
          children: [
            if (showBack)
              TextButton(
                onPressed: busy ? null : onBack,
                style: TextButton.styleFrom(
                  foregroundColor: stoopCream2(context),
                ),
                child: const Text('Back'),
              ),
            const Spacer(),
            StoopAmberButton(
              label: isLast ? 'Submit for review' : 'Next',
              busy: busy,
              onPressed: (canAdvance && !busy) ? onNext : null,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
            ),
          ],
        ),
      ),
    );
  }
}
