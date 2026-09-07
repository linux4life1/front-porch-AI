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

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/waifu/waifu_delete_session_dialog.dart';
import 'package:front_porch_ai/ui/pages/home/cards/home_card_menu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One sit-down folder on the Waifu Coder home grid. Tap resumes. Right-click
/// or ⋮ offers New session in that folder.
class WaifuProjectCard extends StatefulWidget {
  const WaifuProjectCard({
    super.key,
    required this.project,
    required this.onResume,
    required this.onNewSession,
    this.onForget,
    this.isNewest = false,
    this.index = 0,
  });

  final WaifuProject project;
  final VoidCallback onResume;
  final VoidCallback onNewSession;
  final VoidCallback? onForget;
  final bool isNewest;
  final int index;

  @override
  State<WaifuProjectCard> createState() => _WaifuProjectCardState();
}

class _WaifuProjectCardState extends State<WaifuProjectCard> {
  var _hot = false;

  void _menu(Offset global) {
    final amber = AppColors.porchAmberOf(context);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(global.dx, global.dy, global.dx, 0),
      color: AppColors.surfaceContainerOf(context),
      items: [
        homeCardMenuItem(
          context,
          value: 'resume',
          icon: Icons.play_arrow_rounded,
          label: 'Resume',
          iconColor: amber,
        ),
        homeCardMenuItem(
          context,
          value: 'new',
          icon: Icons.add_comment_outlined,
          label: 'New session',
          iconColor: amber,
        ),
        if (widget.onForget != null)
          homeCardMenuItem(
            context,
            value: 'forget',
            icon: Icons.delete_outline,
            label: 'Delete this session',
            iconColor: AppColors.negativeAccentOf(context),
            labelColor: AppColors.negativeAccentOf(context),
          ),
      ],
    ).then((v) async {
      if (v == 'resume') widget.onResume();
      if (v == 'new') widget.onNewSession();
      if (v == 'forget') {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => WaifuDeleteSessionDialog(project: widget.project),
        );
        if (ok == true) widget.onForget?.call();
      }
    });
  }

  Widget _face(BuildContext context, Color amber) {
    final path = widget.project.coworker.imagePath;
    final file = (path == null || path.isEmpty) ? null : File(path);
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: amber.withValues(alpha: _hot ? 0.7 : 0.4),
            blurRadius: _hot ? 22 : 12,
          ),
        ],
        border: Border.all(color: amber, width: 2.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: CharacterPortrait(size: 76, file: file, shrinkIfEmpty: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final honey = AppColors.porchHoneyOf(context);
    final terra = AppColors.porchTerracottaOf(context);
    final chaos = AppColors.chaosAccentOf(context);
    final delay = widget.index * 70;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + delay),
      curve: Curves.easeOutBack,
      builder: (context, t, child) {
        final clamped = t.clamp(0.0, 1.0);
        return Opacity(
          opacity: clamped,
          child: Transform.translate(
            offset: Offset(0, (1 - clamped) * 28),
            child: child,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hot = true),
        onExit: (_) => setState(() => _hot = false),
        child: AnimatedScale(
          scale: _hot ? 1.05 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: amber.withValues(alpha: _hot ? 0.55 : 0.22),
                  blurRadius: _hot ? 26 : 12,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: terra.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      amber.withValues(alpha: _hot ? 0.55 : 0.32),
                      honey.withValues(alpha: 0.22),
                      terra.withValues(alpha: 0.16),
                      AppColors.cardOf(context),
                    ],
                    stops: const [0, 0.28, 0.58, 1],
                  ),
                  border: Border.all(
                    color: _hot ? chaos : amber,
                    width: _hot ? 2.4 : 1.4,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 18,
                      child: Container(
                        width: 54,
                        height: 12,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [honey, amber]),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: InkWell(
                        key: widget.isNewest
                            ? const Key('waifu-resume')
                            : Key('waifu-project-${widget.project.folderName}'),
                        borderRadius: BorderRadius.circular(22),
                        onTap: widget.onResume,
                        onSecondaryTapUp: (d) => _menu(d.globalPosition),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _face(context, amber),
                              const SizedBox(height: 10),
                              Text(
                                widget.project.folderName,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: honey.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: honey.withValues(alpha: 0.7),
                                  ),
                                ),
                                child: Text(
                                  widget.project.coworker.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: honey,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (widget.project.title.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  widget.project.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.textSecondary(context),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              if (widget.isNewest) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'LATEST',
                                  style: TextStyle(
                                    color: chaos,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 10,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 4,
                      child: IconButton(
                        key: Key(
                          'waifu-project-menu-${widget.project.folderName}',
                        ),
                        icon: Icon(Icons.more_vert, color: amber, size: 20),
                        onPressed: () {
                          final box = context.findRenderObject() as RenderBox?;
                          final origin =
                              box?.localToGlobal(Offset.zero) ?? Offset.zero;
                          _menu(origin + const Offset(40, 12));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
