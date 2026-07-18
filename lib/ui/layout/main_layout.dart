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
import 'package:flutter/services.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/engine_health.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/sidebar.dart';
import 'package:front_porch_ai/ui/pages/home_page.dart';
import 'package:front_porch_ai/ui/pages/create_character_page.dart';
import 'package:front_porch_ai/ui/pages/model_manager_page.dart';
import 'package:front_porch_ai/ui/pages/settings_page.dart';
import 'package:front_porch_ai/ui/pages/user_persona_page.dart';
import 'package:front_porch_ai/ui/pages/world_management_page.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/providers/app_state.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final List<Widget> _pages = [
    const HomePage(),
    const CreateCharacterPage(),
    const ModelManagerPage(),
    const SettingsPage(),
    const UserPersonaPage(),
    const WorldManagementPage(),
  ];

  @override
  void initState() {
    super.initState();
    // Pre-release builds surface the first unexpected engine failure of the
    // session as a report-it notice: a quietly-broken engine is otherwise
    // indistinguishable from a working one (sidecar retirement playbook),
    // and users only report what visibly breaks.
    EngineHealth.instance.onFirstFailure = _showEngineFailureNotice;
  }

  @override
  void dispose() {
    if (EngineHealth.instance.onFirstFailure == _showEngineFailureNotice) {
      EngineHealth.instance.onFirstFailure = null;
    }
    super.dispose();
  }

  void _showEngineFailureNotice(String engine, String reason) {
    if (!isPreRelease || !mounted) return;
    // Engines report from service code that may be mid-frame; defer so the
    // snackbar never fires during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.porchAmberOf(context),
          duration: const Duration(seconds: 10),
          // Without persist:false, action snackbars never auto-dismiss.
          persist: false,
          content: Text(
            '⚠️ $engine hit an engine error — please report this on '
            'Discord.',
            style: const TextStyle(color: AppColors.onChaosAccent),
          ),
          action: SnackBarAction(
            label: 'Copy details',
            textColor: AppColors.onChaosAccent,
            onPressed: () => Clipboard.setData(
              ClipboardData(text: EngineHealth.instance.buildReport()),
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch AppState to rebuild on index change
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      body: Row(
        children: [
          const Sidebar(),
          Expanded(
            child:
                _pages[appState.selectedIndex < _pages.length
                    ? appState.selectedIndex
                    : 0],
          ),
        ],
      ),
    );
  }
}
