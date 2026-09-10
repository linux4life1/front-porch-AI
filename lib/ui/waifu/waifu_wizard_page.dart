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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/waifu/waifu_home_atmosphere.dart';
import 'package:front_porch_ai/ui/waifu/waifu_page.dart';
import 'package:front_porch_ai/ui/waifu/waifu_wizard_coworker_step.dart';
import 'package:front_porch_ai/ui/waifu/waifu_wizard_project_step.dart';
import 'package:front_porch_ai/ui/waifu/waifu_wizard_sit_down_step.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Project → Coworker → Sit down. Create Character chrome, linear only.
class WaifuWizardPage extends StatefulWidget {
  const WaifuWizardPage({
    super.key,
    this.characters,
    this.toolsSupported = true,
    this.isLocalBackend = false,
    this.backendLabel = '',
    this.initialFolder,
    this.initialCoworker,
    this.skipProject = false,
    this.onSatDown,
    this.listDirectory,
    this.store,
  });

  final List<CharacterCard>? characters;
  final bool toolsSupported;
  final bool isLocalBackend;
  final String backendLabel;
  final String? initialFolder;
  final CharacterCard? initialCoworker;
  final bool skipProject;
  final void Function(WaifuSession session)? onSatDown;

  /// Test seam. Production uses [listWaifuDirectory].
  final Future<WaifuFolderListing> Function(String path)? listDirectory;

  /// When this porch already has pathMode + honesty, skip the re-quiz
  /// for that scope. Jail/Disk radios stay so the porch can switch.
  final WaifuStore? store;

  @override
  State<WaifuWizardPage> createState() => _WaifuWizardPageState();
}

class _WaifuWizardPageState extends State<WaifuWizardPage> {
  static const _labels = ['Project', 'Coworker', 'Sit down'];

  int _currentStep = 0;
  late String _path;
  WaifuFolderListing? _listing;
  bool _loading = true;
  bool _folderConfirmed = false;
  CharacterCard? _coworker;
  bool _honesty = false;
  bool _skipHonesty = false;
  WaifuPorchConsent? _consent;
  WaifuMode _mode = WaifuMode.build;
  WaifuPathMode _pathMode = WaifuPathMode.folderJail;

  @override
  void initState() {
    super.initState();
    _path = widget.initialFolder ?? waifuDefaultStartPath();
    _coworker = widget.initialCoworker;
    if (widget.skipProject && widget.initialFolder != null) {
      _folderConfirmed = true;
      _currentStep = widget.initialCoworker == null ? 1 : 2;
    }
    _load();
    _hydrateConsent();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final listFn = widget.listDirectory ?? listWaifuDirectory;
    final listing = await listFn(_path);
    if (!mounted) return;
    setState(() {
      _listing = listing;
      _loading = false;
    });
  }

  void _open(String path) {
    setState(() {
      _path = path;
      _folderConfirmed = false;
      _honesty = false;
      _skipHonesty = false;
      _consent = null;
      _pathMode = WaifuPathMode.folderJail;
    });
    _load();
    _hydrateConsent();
  }

  Future<void> _hydrateConsent() async {
    final store = widget.store;
    if (store == null || _path.isEmpty) return;
    final consent = await store.loadPorchConsent(_path);
    if (!mounted) return;
    if (!waifuSkipHonestyQuiz(consent)) return;
    setState(() {
      _consent = consent;
      _pathMode = consent!.pathMode;
      _skipHonesty = waifuHideHonestyForScope(
        consent: consent,
        pathMode: consent.pathMode,
      );
      _honesty = _skipHonesty;
    });
  }

  List<CharacterCard> get _cards {
    if (widget.characters != null) return widget.characters!;
    try {
      return context.read<CharacterRepository>().characters;
    } catch (_) {
      return const [];
    }
  }

  bool get _canNext {
    if (_currentStep == 0) return _folderConfirmed;
    if (_currentStep == 1) return _coworker != null;
    return false;
  }

  Future<void> _confirm() async {
    final coworker = _coworker;
    if (coworker == null) return;
    final session = WaifuSession(
      folderRoot: _path,
      coworker: coworker,
      mode: _mode,
      pathMode: _pathMode,
      toolsSupported: widget.toolsSupported,
    );
    final onSat = widget.onSatDown;
    if (onSat != null) {
      onSat(session);
      return;
    }
    await waifuLoadTodos(_path, session.todos);
    await waifuPrepareLangs(session);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => WaifuPage(session: session)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: amber, size: 22),
            const SizedBox(width: 8),
            const Text(kWaifuCoderName),
            const Spacer(),
            _stepIndicator(),
          ],
        ),
      ),
      body: WaifuHomeAtmosphere(
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: KeyedSubtree(
                  key: ValueKey(_currentStep),
                  child: _body(),
                ),
              ),
            ),
            if (_currentStep < 2) _nav(),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_currentStep) {
      case 0:
        return WaifuWizardProjectStep(
          listing: _listing,
          loading: _loading,
          folderConfirmed: _folderConfirmed,
          onOpen: _open,
          onUseThisFolder: () => setState(() => _folderConfirmed = true),
        );
      case 1:
        return WaifuWizardCoworkerStep(
          characters: _cards,
          selected: _coworker,
          onSelected: (c) => setState(() => _coworker = c),
        );
      default:
        return WaifuWizardSitDownStep(
          folderPath: _path,
          coworker: _coworker,
          backendLabel: widget.backendLabel,
          isLocalBackend: widget.isLocalBackend,
          toolsSupported: widget.toolsSupported,
          mode: _mode,
          pathMode: _pathMode,
          honestyAccepted: _honesty,
          onModeChanged: (m) => setState(() => _mode = m),
          onPathModeChanged: (scope) => setState(() {
            _pathMode = scope;
            _skipHonesty = waifuHideHonestyForScope(
              consent: _consent,
              pathMode: scope,
            );
            _honesty = _skipHonesty;
          }),
          onHonestyChanged: (v) => setState(() => _honesty = v),
          onConfirm: _confirm,
          skipHonestyQuiz: _skipHonesty,
        );
    }
  }

  Widget _stepIndicator() {
    final children = <Widget>[];
    for (var i = 0; i < _labels.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            width: 24,
            height: 2,
            margin: const EdgeInsets.only(bottom: 14),
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        );
      }
      children.add(_dot(i, _labels[i]));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _dot(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    final amber = AppColors.porchAmberOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? amber : AppColors.surfaceContainerOf(context),
            border: Border.all(
              color: isCurrent
                  ? AppColors.textPrimary(context)
                  : AppColors.borderOf(context).withValues(alpha: 0.3),
              width: isCurrent ? 2 : 1,
            ),
          ),
          child: Center(
            child: isActive && !isCurrent
                ? Icon(Icons.check, size: 14, color: AppColors.onChaosAccent)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive
                          ? AppColors.onChaosAccent
                          : AppColors.textTertiary(context),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive
                ? AppColors.textSecondary(context)
                : AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }

  Widget _nav() {
    final nextLabel = _currentStep == 0 ? 'Next: Coworker' : 'Next: Sit down';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_currentStep > 0)
            OutlinedButton.icon(
              onPressed: () => setState(() => _currentStep -= 1),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary(context),
                side: BorderSide(color: AppColors.borderOf(context)),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 16),
          SizedBox(
            width: 240,
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('waifu-wizard-next'),
              onPressed: _canNext
                  ? () => setState(() => _currentStep += 1)
                  : null,
              icon: const Icon(Icons.arrow_forward, size: 20),
              label: Text(nextLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.porchAmberOf(context),
                foregroundColor: AppColors.onChaosAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
