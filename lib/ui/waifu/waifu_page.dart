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
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/waifu/waifu_ask_dialog.dart';
import 'package:front_porch_ai/ui/waifu/waifu_coworker_face.dart';
import 'package:front_porch_ai/ui/waifu/waifu_language_help.dart';
import 'package:front_porch_ai/ui/waifu/waifu_mcp_bind.dart';
import 'package:front_porch_ai/ui/waifu/waifu_photo_vision.dart';
import 'package:front_porch_ai/ui/waifu/waifu_question_dialog.dart';
import 'package:front_porch_ai/ui/waifu/waifu_composer.dart';
import 'package:front_porch_ai/ui/waifu/waifu_session_chrome.dart';
import 'package:front_porch_ai/ui/waifu/waifu_session_controller.dart';
import 'package:front_porch_ai/ui/waifu/waifu_session_scope.dart';
import 'package:front_porch_ai/ui/waifu/waifu_sidebar.dart';
import 'package:front_porch_ai/ui/waifu/waifu_status_line.dart';
import 'package:front_porch_ai/ui/waifu/waifu_transcript.dart';
import 'package:front_porch_ai/ui/waifu/waifu_whole_disk_dialog.dart';
import 'package:front_porch_ai/ui/waifu/waifu_work_strip.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Waifu Coder session. Send forwards to managed OpenCode. No Continue, no regen.
class WaifuPage extends StatefulWidget {
  const WaifuPage({super.key, required this.session, this.harness, this.store});

  final WaifuSession session;
  final WaifuHarness? harness;

  /// Test seam. Production uses [StorageService.rootPath]/waifu.
  final WaifuStore? store;

  @override
  State<WaifuPage> createState() => _WaifuPageState();
}

class _WaifuPageState extends State<WaifuPage> {
  final _composer = TextEditingController();
  WaifuSessionController? _bound;
  double _sidebarWidth = SidebarTokens.widthFromEnvironment();

  WaifuSession get _session => widget.session;
  WaifuSessionController get _controller => _bound!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final first = _bound == null;
    if (first) {
      _bound = WaifuSessionController(
        session: widget.session,
        store: waifuStoreForContext(context, injected: widget.store),
      )..onError = _showError;
      _controller.addListener(_refresh);
    }
    final supported = _toolsSupportedOf(context);
    if (supported != null) _controller.setToolsSupported(supported);
    unawaited(
      _controller.followLibraryCard(
        waifuLibraryCard(context, _session.coworker, listen: true),
      ),
    );
    if (!first) return;
    _controller.attach(_bindHarness(context));
    final budget = _contextBudgetFor(_session.genSettings);
    if (budget != null) _controller.setContextBudget(budget);
    unawaited(_controller.armMeter(mcpToolCount: _libraryToolCount(context)));
  }

  @override
  void dispose() {
    _composer.dispose();
    _controller.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Null when this tree has no storage to size against.
  int? _contextBudgetFor(ChatGenerationSettings settings) {
    final StorageService storage;
    try {
      storage = Provider.of<StorageService>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
    String? apiUrl;
    try {
      final llm = Provider.of<LLMProvider>(context, listen: false);
      if (llm.activeBackend == BackendType.omlx) {
        apiUrl = 'http://localhost:8000/v1';
      } else if (llm.activeBackend == BackendType.openRouter) {
        apiUrl = llm.openRouterService.apiUrl;
      }
    } on ProviderNotFoundException {
      // No LLM provider in this tree: use the Porch context size.
    }
    return waifuResolveContextBudget(
      porchContextSize: settings.resolveContextSize(storage),
      apiUrl: apiUrl,
    );
  }

  int _libraryToolCount(BuildContext context) {
    if (!_session.mcpOptIn) return 0;
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      return waifuLoadedToolCardCount(storage.toolsDir);
    } on ProviderNotFoundException {
      return 0;
    } on FileSystemException catch (e) {
      debugPrint('[Waifu] Tool card count failed: $e');
      return 0;
    }
  }

  /// Null when this tree has no ChatService to ask.
  bool? _toolsSupportedOf(BuildContext context) {
    try {
      final chat = Provider.of<ChatService>(context, listen: false);
      return waifuResolveToolsSupported(
        knownUnsupported: chat.toolCallSupport.name == 'unsupported',
        paused: chat.toolCallingPaused,
      );
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _attachImage() async {
    final bytes = await pickChatImageAttachment(context);
    if (bytes == null || !mounted) return;
    await _acceptImageBytes(bytes);
  }

  Future<void> _acceptImageBytes(Uint8List bytes) async {
    _controller.holdImage(bytes);
    final vision = await resolveWaifuPhotoVision(context);
    if (vision == null) return;
    _controller.setVision(
      bytes,
      ok: vision.supported,
      blindReason: vision.blindReason,
    );
  }

  /// Test trees with neither LLMProvider nor OpenCodeManager get no
  /// harness; Send then says nothing went out.
  WaifuHarness? _bindHarness(BuildContext context) {
    final injected = widget.harness;
    if (injected != null) return injected;
    LLMProvider? provider;
    OpenCodeManager? oc;
    try {
      oc = Provider.of<OpenCodeManager>(context, listen: false);
    } on ProviderNotFoundException {
      // OpenCode is optional; the harness falls back to the LLM provider.
    }
    try {
      provider = Provider.of<LLMProvider>(context, listen: false);
    } on ProviderNotFoundException {
      if (oc == null) return null;
    }
    return waifuBindSessionHarness(
      session: _session,
      provider: provider,
      manager: oc,
      store: _controller.store,
      onAsk: _ask,
      onQuestion: _askQuestion,
      mcpConfigOf: () => waifuOpenCodeMcpMap(context, optIn: _session.mcpOptIn),
      skillsDirOf: () {
        try {
          return Provider.of<StorageService>(context, listen: false).skillsDir;
        } on ProviderNotFoundException {
          return null;
        }
      },
    );
  }

  Future<WaifuAskDecision> _ask(WaifuAskRequest request) async {
    if (!mounted) return WaifuAskDecision.deny;
    final result = await showDialog<WaifuAskDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WaifuAskDialog(
        request: request,
        name: WaifuStage.of(_session).name,
        portrait: waifuCoworkerFace(context, _session.coworker),
      ),
    );
    return result ?? WaifuAskDecision.deny;
  }

  Future<String> _askQuestion(WaifuQuestionRequest request) async {
    if (!mounted) return '';
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WaifuQuestionDialog(
        request: request,
        name: WaifuStage.of(_session).name,
        portrait: waifuCoworkerFace(context, _session.coworker),
      ),
    );
    return result ?? '';
  }

  Future<void> _setPathMode(WaifuPathMode next) async {
    if (_session.pathMode == next) return;
    if (next == WaifuPathMode.wholeDisk) {
      final ok = await showWaifuWholeDiskHonesty(context);
      if (!ok || !mounted) return;
    }
    await _controller.setPathMode(next);
  }

  void _onGenSettings(ChatGenerationSettings next) {
    unawaited(
      _controller.setGenSettings(next, contextBudget: _contextBudgetFor(next)),
    );
  }

  String _langDirOf(BuildContext context) {
    var dir = p.join(_session.folderRoot, kWaifuDotDir, 'lang');
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final root = storage.rootPath;
      if (root != null && root.isNotEmpty) {
        dir = p.join(waifuStoreDirectory(root), 'lang');
      }
    } on ProviderNotFoundException {
      // No storage in this tree: keep languages beside the session folder.
    }
    return dir;
  }

  void _openLanguageHelp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WaifuLanguageHelp(
          langs: _controller.langs(() => _langDirOf(context)),
          suggested: _session.suggestedLangs,
        ),
      ),
    );
  }

  Future<void> _send() =>
      _controller.send(_composer.text, onAccepted: _composer.clear);

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final c = _controller;
    final amber = AppColors.porchAmberOf(context);
    final harness = c.harness;
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
                  child: WaifuTranscript(
                    session: session,
                    coworker: session.coworker.name,
                  ),
                ),
                if (waifuTurnReceiptVisible(
                  lastWrite: session.lastWrite,
                  writes: session.turnWrites,
                ))
                  WaifuWorkStrip(
                    record: session.lastWrite ?? session.turnWrites.last,
                    name: WaifuStage.of(session).name,
                    writes: session.turnWrites,
                    verifiedPaths: session.turnVerifyPaths,
                    onClose: c.dismissReceipt,
                  ),
                WaifuStatusLine(session: session),
                WaifuComposer(
                  controller: _composer,
                  session: session,
                  onSend: _send,
                  onStop: c.abort,
                  onRemoveQueued: c.removeQueued,
                  onUndo: c.undo,
                  onRedo: c.redo,
                  canUndo: c.canUndo,
                  canRedo: c.canRedo,
                  pendingImage: c.pendingImage,
                  visionOk: c.visionOk,
                  blindReason: c.blindReason,
                  onAttach: _attachImage,
                  onRemoveImage: c.dropImage,
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
              onMode: c.setMode,
              onPathMode: _setPathMode,
              onPreserveThinking: c.setPreserveThinking,
              onToolsOptIn: c.setToolsOptIn,
              harness: harness,
              onThemeOverrides: c.setThemeOverrides,
              onGenSettings: _onGenSettings,
              onCompact: harness == null ? null : c.compact,
            ),
          ),
        ],
      ),
    );
  }
}
