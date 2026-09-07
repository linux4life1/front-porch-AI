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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/desk/desk_home_atmosphere.dart';
import 'package:front_porch_ai/ui/desk/desk_new_porch_card.dart';
import 'package:front_porch_ai/ui/desk/desk_new_session_dialog.dart';
import 'package:front_porch_ai/ui/desk/desk_page.dart';
import 'package:front_porch_ai/ui/desk/desk_project_card.dart';
import 'package:front_porch_ai/ui/desk/desk_wizard_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Third home pane. Touched folders become porch cards. New opens the
/// folder → character wizard.
class DeskHomeView extends StatefulWidget {
  const DeskHomeView({
    super.key,
    this.onSitDown,
    this.lastSession,
    this.onResume,
    this.store,
    this.projects,
  });

  final VoidCallback? onSitDown;
  final DeskSession? lastSession;
  final VoidCallback? onResume;
  final DeskStore? store;
  final List<DeskProject>? projects;

  @override
  State<DeskHomeView> createState() => _DeskHomeViewState();
}

class _DeskHomeViewState extends State<DeskHomeView> {
  List<DeskProject> _stored = const [];
  var _routeCurrent = false;

  List<DeskProject> get _projects {
    if (widget.projects != null) return widget.projects!;
    if (widget.lastSession != null) {
      final s = widget.lastSession!;
      return [
        DeskProject(
          folderRoot: s.folderRoot,
          title: s.title,
          coworker: s.coworker,
          touchedMs: 1,
        ),
      ];
    }
    return _stored;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.lastSession != null || widget.projects != null) return;
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current && !_routeCurrent) _load();
    _routeCurrent = current;
  }

  Future<void> _load() async {
    final store = _storeOf();
    if (store == null) return;
    final list = await store.listProjects();
    if (!mounted) return;
    setState(() => _stored = list);
  }

  DeskStore? _storeOf() {
    if (widget.store != null) return widget.store;
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final root = storage.rootPath;
      if (root == null || root.isEmpty) return null;
      return DeskStore(deskStoreDirectory(root));
    } catch (_) {
      return null;
    }
  }

  void _startNew({String? folder, bool skipProject = false}) {
    if (widget.onSitDown != null && folder == null) {
      widget.onSitDown!();
      return;
    }
    var local = false;
    var label = '';
    try {
      final llm = Provider.of<LLMProvider>(context, listen: false);
      local = llm.isLocal;
      label = local ? 'local Kobold' : 'remote';
    } catch (_) {}
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeskWizardPage(
          isLocalBackend: local,
          backendLabel: label,
          initialFolder: folder,
          skipProject: skipProject,
        ),
      ),
    );
  }

  Future<void> _resume(DeskProject project) async {
    if (widget.onResume != null) {
      widget.onResume!();
      return;
    }
    final store = _storeOf();
    final session =
        await store?.loadSession(project.folderRoot) ??
        DeskSession(
          folderRoot: project.folderRoot,
          coworker: project.coworker,
          title: project.title,
        );
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => DeskPage(session: session)));
    _load();
  }

  Future<void> _newInFolder(DeskProject project) async {
    final choice = await showDialog<DeskNewSessionChoice>(
      context: context,
      builder: (_) => DeskNewSessionDialog(project: project),
    );
    if (!mounted || choice == null) return;
    if (choice == DeskNewSessionChoice.sameCharacter) {
      final session = DeskSession(
        folderRoot: project.folderRoot,
        coworker: project.coworker,
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DeskPage(session: session)),
      );
      _load();
      return;
    }
    _startNew(folder: project.folderRoot, skipProject: true);
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final honey = AppColors.porchHoneyOf(context);
    final terra = AppColors.porchTerracottaOf(context);
    final projects = _projects;
    return DeskHomeAtmosphere(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 8),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [amber, honey, terra],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: amber.withValues(alpha: 0.55),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    color: AppColors.onChaosAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [amber, honey, terra],
                        ).createShader(bounds),
                        child: Text(
                          kWaifuCoderName,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: AppColors.onChaosAccent,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              ),
                        ),
                      ),
                      Text(
                        projects.isEmpty
                            ? 'Pick a throwaway folder. She codes in character.'
                            : 'Your porches. Tap to sit back down.',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _grid(projects)),
        ],
      ),
    );
  }

  Widget _grid(List<DeskProject> projects) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        childAspectRatio: 0.70,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
      ),
      itemCount: projects.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return DeskNewPorchCard(index: 0, onTap: () => _startNew());
        }
        final project = projects[i - 1];
        return DeskProjectCard(
          project: project,
          index: i,
          isNewest: i == 1,
          onResume: () => _resume(project),
          onNewSession: () => _newInFolder(project),
          onForget: widget.store == null && widget.lastSession != null
              ? null
              : () async {
                  await _storeOf()?.forgetProject(project.folderRoot);
                  _load();
                },
        );
      },
    );
  }
}
