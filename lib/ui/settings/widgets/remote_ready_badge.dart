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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Compact remote-API status chip. Green is live-reachable only — a
/// configured key with no successful ping is amber "Configured", a failed
/// ping is "Configured but unreachable".
class RemoteReadyBadge extends StatelessWidget {
  const RemoteReadyBadge({super.key, required this.service});

  final OpenRouterService service;

  @override
  Widget build(BuildContext context) {
    final label = remoteBackendStatusLabel(
      configured: service.isConfigured,
      reachability: service.reachability,
    );
    final live = service.isReachable;
    final checking = service.reachability == RemoteReachability.checking;
    final unreachable = service.reachability == RemoteReachability.unreachable;
    // Answered, no model chosen yet: amber, never the red "Not configured".
    final connected = service.reachability == RemoteReachability.reachable;
    final Color color;
    if (live) {
      color = AppColors.resolve(
        context,
        AppColors.logReady,
        AppColors.bondHighLight,
      );
    } else if (checking || connected || service.isConfigured) {
      color = unreachable
          ? AppColors.negativeAccentOf(context)
          : AppColors.porchAmberOf(context);
    } else {
      color = AppColors.negativeAccentOf(context);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (checking)
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
