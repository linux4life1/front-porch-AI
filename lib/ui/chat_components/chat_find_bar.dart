// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:front_porch_ai/ui/chat_components/chat_find_controller.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Platform label for the find shortcut, mirroring chatRegenShortcutLabel.
String get chatFindShortcutLabel => Platform.isMacOS ? '⌘F' : 'Ctrl+F';

/// ⌘F / Ctrl+F opens find-in-chat. Read at the HardwareKeyboard like the
/// regen shortcut — focus can sit in the composer or a bubble, and page-level
/// CallbackShortcuts went dead there before (macOS error sound, 2026-08).
bool handleChatFindShortcut(
  KeyEvent event,
  State host,
  ChatFindController find,
) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyF) {
    return false;
  }
  final keys = HardwareKeyboard.instance;
  if (!(Platform.isMacOS ? keys.isMetaPressed : keys.isControlPressed)) {
    return false;
  }
  if (!host.mounted || !(ModalRoute.of(host.context)?.isCurrent ?? false)) {
    return false;
  }
  find.openFind();
  return true;
}

const double _kBarWidth = 464;

/// Stack wrapper: transcript + the find bar overlaid top-right of it
/// (never over the sidebar — it rides the transcript column).
class ChatFindLayer extends StatelessWidget {
  const ChatFindLayer({
    super.key,
    required this.controller,
    required this.transcript,
  });

  final ChatFindController controller;
  final Widget transcript;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            child!,
            if (controller.open)
              Positioned(
                top: 10,
                right: 16,
                child: ConstrainedBox(
                  // Narrow windows: never wider than the transcript (the
                  // web bar's max-width: calc(100% - 32px)).
                  constraints: BoxConstraints(
                    maxWidth: (box.maxWidth - 32).clamp(0, _kBarWidth),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ChatFindBar(controller: controller),
                  ),
                ),
              ),
          ],
        ),
      ),
      child: FindHighlightScope(controller: controller, child: transcript),
    );
  }
}

/// The find bar: input, Aa / .* toggles, honest counter, prev/next, close —
/// states mirror the reviewed mockup (docs/design/mockups/chat-find-bar.html).
class ChatFindBar extends StatelessWidget {
  const ChatFindBar({super.key, required this.controller});

  final ChatFindController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final bad = controller.badPattern;
        final wild =
            controller.hasQuery &&
            !controller.regexOn &&
            controller.text.text.contains('*');
        final modeChip =
            controller.regexOn && controller.text.text.trim().isNotEmpty
            ? '.* regex'
            : wild
            ? '✱ word wildcard'
            : null;
        return Container(
          width: _kBarWidth,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderOf(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller.text,
                      focusNode: controller.focus,
                      onChanged: (v) => controller.scheduleScan(),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary(context),
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        hintText: controller.waiting
                            ? 'Waiting for older history…'
                            : 'Find in chat…',
                        hintStyle: TextStyle(
                          color: AppColors.textTertiary(context),
                        ),
                        filled: true,
                        fillColor: AppColors.backgroundOf(context),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: bad
                                ? AppColors.logError
                                : AppColors.borderOf(context),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: bad
                                ? AppColors.logError
                                : AppColors.porchHoneyOf(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _toggle(
                    context,
                    label: 'Aa',
                    active: controller.caseSensitive,
                    tooltip: 'Match case',
                    onTap: controller.toggleCase,
                  ),
                  const SizedBox(width: 4),
                  _toggle(
                    context,
                    label: '.*',
                    active: controller.regexOn,
                    tooltip: 'Regular expression',
                    onTap: controller.toggleRegex,
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 78,
                    child: controller.waiting
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.porchHoneyOf(context),
                                ),
                              ),
                            ],
                          )
                        : Text(
                            bad
                                ? 'bad pattern'
                                : controller.text.text.trim().isEmpty
                                ? ''
                                : controller.counterLabel,
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  bad ||
                                      (controller.hasQuery &&
                                          controller.matches.isEmpty)
                                  ? AppColors.logError
                                  : AppColors.textSecondary(context),
                            ),
                          ),
                  ),
                  const SizedBox(width: 6),
                  _icon(
                    context,
                    Icons.arrow_upward,
                    'Previous (⇧↵)',
                    () => controller.step(-1),
                  ),
                  const SizedBox(width: 4),
                  _icon(
                    context,
                    Icons.arrow_downward,
                    'Next (↵)',
                    () => controller.step(1),
                  ),
                  const SizedBox(width: 4),
                  _icon(context, Icons.close, 'Close (Esc)', controller.close),
                ],
              ),
              if (modeChip != null || controller.waiting)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (modeChip != null) ...[
                        _chip(context, modeChip),
                        const SizedBox(width: 8),
                      ],
                      if (controller.waiting && controller.totalCount > 0)
                        Text(
                          'Paging in history — '
                          '${controller.loadedCount} / ${controller.totalCount}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _toggle(
    BuildContext context, {
    required String label,
    required bool active,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final honey = AppColors.porchHoneyOf(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 28,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: active ? honey : AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: active ? honey : AppColors.borderOf(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active
                  ? AppColors.inkOn(honey)
                  : AppColors.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Icon(icon, size: 15, color: AppColors.textSecondary(context)),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label) {
    final honey = AppColors.porchHoneyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: honey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: honey.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: honey)),
    );
  }
}
