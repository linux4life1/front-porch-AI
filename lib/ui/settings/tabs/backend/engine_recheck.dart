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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';

/// Looks for the KoboldCpp engine again each time [child] opens, so an
/// engine file removed since the last look shows as missing straight away
/// rather than "Ready" with the old path until Start is pressed.
class EngineRecheck extends StatefulWidget {
  const EngineRecheck({super.key, required this.child});

  final Widget child;

  @override
  State<EngineRecheck> createState() => _EngineRecheckState();
}

class _EngineRecheckState extends State<EngineRecheck> {
  @override
  void initState() {
    super.initState();
    unawaited(
      context.read<BackendManager>().checkBackendAvailability().catchError(
        (Object e) => debugPrint('[Backend] engine re-check failed: $e'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
