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

import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/desk/desk_ask_dialog.dart';
import 'package:front_porch_ai/ui/desk/desk_coworker_face.dart';
import 'package:front_porch_ai/ui/desk/desk_language_help.dart';
import 'package:front_porch_ai/ui/desk/desk_mcp_bind.dart';
import 'package:front_porch_ai/ui/desk/desk_question_dialog.dart';
import 'package:front_porch_ai/ui/desk/desk_composer.dart';
import 'package:front_porch_ai/ui/desk/desk_sidebar.dart';
import 'package:front_porch_ai/ui/desk/desk_tool_log.dart';
import 'package:front_porch_ai/ui/desk/desk_work_strip.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/capability/capability.dart';

part 'desk_page_image.dart';

/// Desk session. Send runs the in-process tool loop. No Continue, no regen.
class DeskPage extends StatefulWidget {
  const DeskPage({
    super.key,
    required this.session,
    this.harness,
    this.llm,
    this.store,
    this.skills,
  });

  final DeskSession session;
  final DeskHarness? harness;
  final DeskLlm? llm;

  /// Test seam. Production uses [StorageService.rootPath]/desk.
  final DeskStore? store;

  /// Test seam. Production builds a hub for the sit-down folder.
  final DeskSkillHub? skills;

  @override
  State<DeskPage> createState() => _DeskPageState();
}

class _DeskPageState extends State<DeskPage> {
  final _composer = TextEditingController();
  DeskHarness? _created;
  DeskSkillHub? _skills;
  double _sidebarWidth = SidebarTokens.widthFromEnvironment();
  var _parked = false;
  Uint8List? _pendingImage;
  bool? _pendingVisionOk;
  String? _pendingBlindReason;

  @override
  void initState() {
    super.initState();
    widget.harness?.onChanged = _refresh;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_parked) return;
    _parked = true;
    _storeOf(context)?.saveLast(widget.session);
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      widget.session.contextBudget = widget.session.genSettings
          .resolveContextSize(storage);
    } catch (_) {}
  }

  @override
  void dispose() {
    _composer.dispose();
    widget.session.langs?.killAll();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void rebuildState(VoidCallback fn) => setState(fn);

  DeskStore? _storeOf(BuildContext context) {
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

  DeskSkillHub _skillsOf() {
    final fromHarness = (widget.harness ?? _created)?.skills;
    if (fromHarness != null) return fromHarness;
    if (widget.skills != null) return widget.skills!;
    return _skills ??= DeskSkillHub(
      projectRoot: widget.session.folderRoot,
      userSkillsDir: deskUserSkillsDir(),
    );
  }

  DeskHarness? _harnessOf(BuildContext context) {
    final injected = widget.harness;
    if (injected != null) return injected;
    if (_created != null) return _created;
    final store = _storeOf(context);
    final llm = widget.llm;
    final mcp = deskMcpBind(context);
    final webSearch = deskWebSearchBind(context);
    final skills = _skillsOf();
    if (llm != null) {
      return _created = DeskHarness(
        session: widget.session,
        llm: llm,
        store: store,
        onChanged: _refresh,
        onAsk: _ask,
        onQuestion: _askQuestion,
        mcpTools: mcp.tools,
        mcpCall: mcp.call,
        mcpOptIn: widget.session.mcpOptIn,
        webSearch: webSearch,
        skills: skills,
      );
    }
    try {
      final provider = Provider.of<LLMProvider>(context, listen: false);
      StorageService? storage;
      try {
        storage = Provider.of<StorageService>(context, listen: false);
      } catch (_) {}
      return _created = DeskHarness(
        session: widget.session,
        llm: LlmServiceDeskLlm(
          () => provider.activeService,
          settingsOf: () => widget.session.genSettings,
          storage: storage,
          remainingTokensOf: () => deskOutputTokenBudget(
            budget: widget.session.contextBudget,
            used: widget.session.tokensUsed,
          ),
          reasoningEnabled: storage?.reasoningEnabled ?? false,
          reasoningEffort: storage?.reasoningEffort ?? 'medium',
        ),
        store: store,
        onChanged: _refresh,
        onAsk: _ask,
        onQuestion: _askQuestion,
        mcpTools: mcp.tools,
        mcpCall: mcp.call,
        mcpOptIn: widget.session.mcpOptIn,
        webSearch: webSearch,
        skills: skills,
      );
    } catch (_) {
      return null;
    }
  }

  Future<DeskAskDecision> _ask(DeskAskRequest request) async {
    if (!mounted) return DeskAskDecision.deny;
    final result = await showDialog<DeskAskDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeskAskDialog(request: request),
    );
    return result ?? DeskAskDecision.deny;
  }

  Future<String> _askQuestion(DeskQuestionRequest request) async {
    if (!mounted) return '';
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeskQuestionDialog(request: request),
    );
    return result ?? '';
  }

  void _setMode(DeskMode mode) {
    setState(() => widget.session.mode = mode);
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
      widget.session.transcript.add(DeskMessage(isUser: false, text: line));
    });
  }

  DeskLangRuntime _langsOf(BuildContext context) {
    final existing = widget.session.langs;
    if (existing != null) return existing;
    String dir = p.join(widget.session.folderRoot, kWaifuDotDir, 'lang');
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final root = storage.rootPath;
      if (root != null && root.isNotEmpty) {
        dir = p.join(deskStoreDirectory(root), 'lang');
      }
    } catch (_) {}
    return widget.session.langs = DeskLangRuntime(directory: dir);
  }

  void _openLanguageHelp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeskLanguageHelp(
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
      imagePath = await deskSaveInboxPhoto(widget.session.folderRoot, photo);
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
          DeskMessage(
            isUser: true,
            text: text.isEmpty ? '(photo)' : text,
            imagePath: imagePath,
          ),
        );
      });
      return;
    }
    await harness.send(text, imagePng: photo, imagePath: imagePath);
  }

  void _pickSlash(DeskSlashCommand cmd) {
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
    final cmd = deskSlashExact(text);
    if (cmd == null || !cmd.local) return false;
    final session = widget.session;
    final mode = deskSlashMode(cmd.name);
    if (mode != null) {
      setState(() {
        session.mode = mode;
        session.transcript.add(
          DeskMessage(isUser: false, text: 'Mode is ${mode.name}.'),
        );
      });
      return true;
    }
    switch (cmd.name) {
      case 'help':
        setState(() {
          session.transcript.add(
            DeskMessage(isUser: false, text: deskSlashHelpText()),
          );
        });
        return true;
      case 'undo':
        _harnessOf(context)?.undo();
        return true;
      case 'stop':
        _harnessOf(context)?.abort();
        return true;
      case 'compact':
        setState(() {
          final next = deskCompactTranscript(
            session.transcript,
            budgetTokens: session.contextBudget,
          );
          session.transcript
            ..clear()
            ..addAll(next);
          session.transcript.add(
            const DeskMessage(isUser: false, text: 'Folded old turns.'),
          );
        });
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
    final folderName = p.basename(session.folderRoot);
    final harness = widget.harness ?? _created;
    final coworker = session.coworker.name;
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.title.isEmpty ? coworker : session.title),
            Text(
              folderName,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('desk-language-help'),
            tooltip: 'Language help',
            onPressed: _openLanguageHelp,
            icon: Icon(Icons.translate, color: amber),
          ),
          IconButton(
            key: const Key('desk-toggle-sidebar'),
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
                Expanded(child: _transcript(session, coworker)),
                if (session.lastWrite != null)
                  DeskWorkStrip(
                    record: session.lastWrite!,
                    onClose: () => setState(() => session.lastWrite = null),
                  ),
                DeskComposer(
                  controller: _composer,
                  session: session,
                  onSend: _send,
                  onPickSlash: _pickSlash,
                  onStop: () => _harnessOf(context)?.abort(),
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
            child: DeskSidebar(
              session: session,
              portrait: deskCoworkerFace(context, session.coworker),
              mcpOptIn: session.mcpOptIn,
              onMcpOptIn: (v) {
                setState(() {
                  session.mcpOptIn = v;
                  final h = widget.harness ?? _created ?? _harnessOf(context);
                  if (h != null) h.mcpOptIn = v;
                });
              },
              onMode: _setMode,
              onPreserveThinking: (v) {
                setState(() => session.preserveThinking = v);
                unawaited(_storeOf(context)?.saveLast(session));
              },
              todos: harness?.todos,
              mcpLine: deskMcpStatusLine(context),
              skills: _skillsOf(),
              onSkillsChanged: _refresh,
            ),
          ),
        ],
      ),
    );
  }

  Widget _transcript(DeskSession session, String coworker) {
    if (session.transcript.isEmpty) {
      return Center(
        child: Text(
          'Tell $coworker what to do. Tools loop in this folder.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }
    final chats = [
      for (final m in session.transcript) m.toChatMessage(coworker),
    ];
    return ChatMessageList(
      messages: chats,
      resolveSpeaker: (msg) => msg.isUser
          ? (null, null)
          : (deskCoworkerFace(context, session.coworker), null),
      characterFor: (_) => session.coworker,
      isGenerating: session.running,
      generatingAt: (i) => session.running && i == chats.length - 1,
      aboveBubble: (msg, index) {
        if (msg.isUser) return null;
        if (index < 0 || index >= session.transcript.length) return null;
        final chips = session.transcript[index].chips;
        if (chips.isEmpty) return null;
        return DeskToolLog(chips: chips);
      },
    );
  }
}
