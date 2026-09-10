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
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/waifu/waifu_ask_dialog.dart';
import 'package:front_porch_ai/ui/waifu/waifu_coworker_face.dart';
import 'package:front_porch_ai/ui/waifu/waifu_language_help.dart';
import 'package:front_porch_ai/ui/waifu/waifu_mcp_bind.dart';
import 'package:front_porch_ai/ui/waifu/waifu_question_dialog.dart';
import 'package:front_porch_ai/ui/waifu/waifu_composer.dart';
import 'package:front_porch_ai/ui/waifu/waifu_plan_stage.dart';
import 'package:front_porch_ai/ui/waifu/waifu_session_chrome.dart';
import 'package:front_porch_ai/ui/waifu/waifu_session_scope.dart';
import 'package:front_porch_ai/ui/waifu/waifu_sidebar.dart';
import 'package:front_porch_ai/ui/waifu/waifu_transcript.dart';
import 'package:front_porch_ai/ui/waifu/waifu_whole_disk_dialog.dart';
import 'package:front_porch_ai/ui/waifu/waifu_work_strip.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/capability/capability.dart';

part 'waifu_page_image.dart';

/// Waifu Coder session. Send runs the in-process tool loop. No Continue, no regen.
class WaifuPage extends StatefulWidget {
  const WaifuPage({
    super.key,
    required this.session,
    this.harness,
    this.llm,
    this.store,
    this.skills,
  });

  final WaifuSession session;
  final WaifuHarness? harness;
  final WaifuLlm? llm;

  /// Test seam. Production uses [StorageService.rootPath]/waifu.
  final WaifuStore? store;

  /// Test seam. Production builds a hub for the sit-down folder.
  final WaifuSkillHub? skills;

  @override
  State<WaifuPage> createState() => _WaifuPageState();
}

class _WaifuPageState extends State<WaifuPage> {
  final _composer = TextEditingController();
  WaifuHarness? _created;
  WaifuSkillHub? _skills;
  double _sidebarWidth = SidebarTokens.widthFromEnvironment();
  var _parked = false;
  Uint8List? _pendingImage;
  bool? _pendingVisionOk;
  String? _pendingBlindReason;
  String? _lastMcpLine;

  @override
  void initState() {
    super.initState();
    widget.harness?.onChanged = _refresh;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncToolsSupported(context);
    if (_parked) return;
    _parked = true;
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      widget.session.contextBudget = widget.session.genSettings
          .resolveContextSize(storage);
    } catch (_) {}
    waifuArmSessionMeter(
      session: widget.session,
      harness: _harnessOf(context),
      store: _storeOf(context),
    );
  }

  @override
  void dispose() {
    _composer.dispose();
    widget.session.langs?.killAll();
    final h = widget.harness ?? _created;
    if (h != null) {
      h.onChanged = null;
      h.abort();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _syncToolsSupported(BuildContext context) {
    try {
      final chat = Provider.of<ChatService>(context, listen: false);
      widget.session.toolsSupported = waifuResolveToolsSupported(
        knownUnsupported: chat.toolCallSupport.name == 'unsupported',
        paused: chat.toolCallingPaused,
      );
    } catch (_) {}
  }

  void _onThemeChanged() {
    unawaited(_storeOf(context)?.saveLast(widget.session));
    _refresh();
  }

  void rebuildState(VoidCallback fn) => setState(fn);

  WaifuStore? _storeOf(BuildContext context) =>
      waifuStoreForContext(context, injected: widget.store);

  WaifuSkillHub _skillsOf() {
    final fromHarness = (widget.harness ?? _created)?.skills;
    if (fromHarness != null) return fromHarness;
    if (widget.skills != null) return widget.skills!;
    return _skills ??= WaifuSkillHub(
      projectRoot: widget.session.folderRoot,
      userSkillsDir: waifuUserSkillsDir(),
    );
  }

  WaifuHarness? _harnessOf(BuildContext context) {
    final injected = widget.harness;
    if (injected != null) return injected;
    if (_created != null) return _created;
    LLMProvider? provider;
    StorageService? storage;
    try {
      storage = Provider.of<StorageService>(context, listen: false);
    } catch (_) {}
    if (widget.llm == null) {
      try {
        provider = Provider.of<LLMProvider>(context, listen: false);
      } catch (_) {
        return null;
      }
    }
    return _created = waifuBindSessionHarness(
      session: widget.session,
      llm: widget.llm,
      provider: provider,
      storage: storage,
      store: _storeOf(context),
      onChanged: _refresh,
      onAsk: _ask,
      onQuestion: _askQuestion,
      mcpOf: waifuLiveMcpOf(context),
      webSearch: waifuWebSearchBind(context),
      skills: _skillsOf(),
    );
  }

  Future<WaifuAskDecision> _ask(WaifuAskRequest request) async {
    if (!mounted) return WaifuAskDecision.deny;
    final result = await showDialog<WaifuAskDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WaifuAskDialog(request: request),
    );
    return result ?? WaifuAskDecision.deny;
  }

  Future<String> _askQuestion(WaifuQuestionRequest request) async {
    if (!mounted) return '';
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WaifuQuestionDialog(request: request),
    );
    return result ?? '';
  }

  Future<void> _setMode(WaifuMode mode, {bool announce = false}) async {
    final result = await waifuTrySetMode(session: widget.session, next: mode);
    if (!mounted) return;
    setState(() {
      if (result == WaifuModeApply.blockedDraft) {
        widget.session.transcript.add(
          const WaifuMessage.assistant(kWaifuPlanBuildGateCue),
        );
      } else if (announce) {
        widget.session.transcript.add(
          WaifuMessage.assistant('Mode is ${mode.name}.'),
        );
      }
    });
    (widget.harness ?? _created)?.refreshMeter();
  }

  Future<void> _setPathMode(WaifuPathMode next) async {
    if (widget.session.pathMode == next) return;
    if (next == WaifuPathMode.wholeDisk) {
      final ok = await showWaifuWholeDiskHonesty(context);
      if (!ok || !mounted) return;
    }
    final h = widget.harness ?? _created;
    if (h != null) {
      h.applyPathMode(next);
    } else {
      widget.session.pathMode = next;
    }
    unawaited(_storeOf(context)?.saveLast(widget.session));
    if (mounted) setState(() {});
  }

  Future<void> _slashSkills(String text) async {
    final hub = _skillsOf();
    final rest = text
        .trim()
        .replaceFirst(RegExp(r'^/skills\s*', caseSensitive: false), '')
        .trim();
    late final String line;
    if (rest.isEmpty) {
      await hub.refreshLocal();
      await hub.refreshMarket();
      line = hub.listing();
    } else {
      line = await hub.install(rest);
    }
    if (!mounted) return;
    setState(() {
      widget.session.transcript.add(WaifuMessage.assistant(line));
    });
  }

  WaifuLangRuntime _langsOf(BuildContext context) {
    final existing = widget.session.langs;
    if (existing != null) return existing;
    String dir = p.join(widget.session.folderRoot, kWaifuDotDir, 'lang');
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final root = storage.rootPath;
      if (root != null && root.isNotEmpty) {
        dir = p.join(waifuStoreDirectory(root), 'lang');
      }
    } catch (_) {}
    return widget.session.langs = WaifuLangRuntime(directory: dir);
  }

  void _openLanguageHelp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WaifuLanguageHelp(
          langs: _langsOf(context),
          suggested: widget.session.suggestedLangs,
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    final photo = _pendingImage;
    if (text.isEmpty && photo == null) return;
    _composer.clear();
    if (photo == null && _applyLocalSlash(text)) return;
    String? imagePath;
    if (photo != null) {
      imagePath = await waifuSaveInboxPhoto(widget.session.folderRoot, photo);
      setState(() {
        _pendingImage = null;
        _pendingVisionOk = null;
        _pendingBlindReason = null;
      });
    }
    final harness = _harnessOf(context);
    if (harness == null) {
      setState(() {
        widget.session.transcript.add(
          WaifuMessage.user(
            text.isEmpty ? '(photo)' : text,
            imagePath: imagePath,
          ),
        );
      });
      return;
    }
    await harness.send(text, imagePng: photo, imagePath: imagePath);
  }

  void _pickSlash(WaifuSlashCommand cmd) {
    if (!cmd.runOnPick) {
      final fill = '/${cmd.name} ';
      _composer.value = TextEditingValue(
        text: fill,
        selection: TextSelection.collapsed(offset: fill.length),
      );
      return;
    }
    _composer.clear();
    if (_applyLocalSlash('/${cmd.name}')) return;
    _harnessOf(context)?.send('/${cmd.name}');
  }

  bool _applyLocalSlash(String text) {
    final cmd = waifuSlashExact(text);
    if (cmd == null || !cmd.local) return false;
    final session = widget.session;
    final mode = waifuSlashMode(cmd.name);
    if (mode != null) {
      unawaited(_setMode(mode, announce: true));
      return true;
    }
    switch (cmd.name) {
      case 'help':
        setState(() {
          session.transcript.add(WaifuMessage.assistant(waifuSlashHelpText()));
        });
        return true;
      case 'undo':
        _harnessOf(context)?.undo();
        return true;
      case 'stop':
        _harnessOf(context)?.abort();
        return true;
      case 'compact':
        unawaited(_harnessOf(context)?.compact());
        return true;
      case 'skills':
        unawaited(_slashSkills(text));
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final amber = AppColors.porchAmberOf(context);
    final harness = _harnessOf(context);
    final coworker = session.coworker.name;
    final mcpLine = waifuMcpStatusLine(context);
    if (mcpLine != _lastMcpLine) {
      _lastMcpLine = mcpLine;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) (widget.harness ?? _created)?.refreshMeter();
      });
    }
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        toolbarHeight: 76,
        title: WaifuSessionChrome(session: session),
        actions: [
          IconButton(
            key: const Key('waifu-language-help'),
            tooltip: 'Language help',
            onPressed: _openLanguageHelp,
            icon: Icon(Icons.translate, color: amber),
          ),
          IconButton(
            key: const Key('waifu-toggle-sidebar'),
            tooltip: 'Toggle Sidebar',
            onPressed: () => setState(
              () => _sidebarWidth = _sidebarWidth > 0
                  ? 0
                  : SidebarTokens.widthFromEnvironment(),
            ),
            icon: Icon(
              _sidebarWidth > 0 ? Icons.last_page : Icons.first_page,
              color: amber,
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                if (!session.toolsSupported)
                  const WaifuToolsUnsupportedBanner(),
                Expanded(
                  child: WaifuTranscript(session: session, coworker: coworker),
                ),
                WaifuPlanStage(
                  session: session,
                  harness: harness,
                  onChanged: _refresh,
                ),
                if (waifuTurnReceiptVisible(
                  lastWrite: session.lastWrite,
                  writes: session.turnWrites,
                ))
                  WaifuWorkStrip(
                    record: session.lastWrite ?? session.turnWrites.last,
                    writes: session.turnWrites,
                    verifiedPaths: session.turnVerifyPaths,
                    onClose: () => setState(() {
                      session.lastWrite = null;
                      session.turnWrites.clear();
                      session.turnVerifyPaths.clear();
                    }),
                  ),
                WaifuComposer(
                  controller: _composer,
                  session: session,
                  onSend: _send,
                  onPickSlash: _pickSlash,
                  onStop: () => _harnessOf(context)?.abort(),
                  onQueueChanged: _refresh,
                  onUndo: () => (widget.harness ?? _created)?.undo(),
                  onRedo: () => (widget.harness ?? _created)?.redo(),
                  canUndo: (widget.harness ?? _created)?.canUndo == true,
                  canRedo: (widget.harness ?? _created)?.canRedo == true,
                  pendingImage: _pendingImage,
                  visionOk: _pendingVisionOk,
                  blindReason: _pendingBlindReason,
                  onAttach: _attachImage,
                  onRemoveImage: () => setState(() {
                    _pendingImage = null;
                    _pendingVisionOk = null;
                    _pendingBlindReason = null;
                  }),
                  onDropImage: _acceptImageBytes,
                ),
              ],
            ),
          ),
          ChatResizeSidebar(
            width: _sidebarWidth,
            onWidth: (w) => setState(() => _sidebarWidth = w),
            child: WaifuSidebar(
              session: session,
              portrait: waifuCoworkerFace(context, session.coworker),
              mcpOptIn: session.mcpOptIn,
              onMcpOptIn: (v) {
                setState(() {
                  session.mcpOptIn = v;
                  final h = widget.harness ?? _created ?? _harnessOf(context);
                  if (h != null) {
                    h.mcpOptIn = v;
                    h.refreshMeter();
                  }
                });
              },
              onMode: _setMode,
              onPathMode: _setPathMode,
              onPreserveThinking: (v) {
                setState(() => session.preserveThinking = v);
                (widget.harness ?? _created)?.refreshMeter();
                unawaited(_storeOf(context)?.saveLast(session));
              },
              harness: harness,
              mcpLine: mcpLine,
              skills: _skillsOf(),
              onSkillsChanged: () {
                (widget.harness ?? _created)?.refreshMeter();
                _refresh();
              },
              onThemeChanged: _onThemeChanged,
              onCompact: harness == null
                  ? null
                  : () => unawaited(harness.compact()),
            ),
          ),
        ],
      ),
    );
  }
}
