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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/waifu/waifu_coworker_face.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class WaifuWizardCoworkerStep extends StatefulWidget {
  const WaifuWizardCoworkerStep({
    super.key,
    required this.characters,
    required this.selected,
    required this.onSelected,
  });

  final List<CharacterCard> characters;
  final CharacterCard? selected;
  final ValueChanged<CharacterCard> onSelected;

  @override
  State<WaifuWizardCoworkerStep> createState() => _WaifuWizardCoworkerStepState();
}

class _WaifuWizardCoworkerStepState extends State<WaifuWizardCoworkerStep> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CharacterCard> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return widget.characters;
    return [
      for (final c in widget.characters)
        if (c.name.toLowerCase().contains(q) ||
            c.tags.any((t) => t.toLowerCase().contains(q)))
          c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final honey = AppColors.porchHoneyOf(context);
    if (widget.characters.isEmpty) {
      return Center(
        child: Text(
          'Create a character first — $kWaifuCoderName needs a coworker.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }
    final visible = _visible;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Coworker',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Who codes with you? One tap. Identity only — no lorebook, no Needs.',
            style: TextStyle(color: honey, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('waifu-coworker-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: AppColors.textPrimary(context)),
            decoration: InputDecoration(
              hintText: 'Search by name or tag…',
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
              prefixIcon: Icon(Icons.search, color: amber),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: amber.withValues(alpha: 0.45)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: amber.withValues(alpha: 0.35)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: amber, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      'No coworker matches “${_search.text.trim()}”.',
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    ),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          childAspectRatio: 0.78,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final card = visible[i];
                      final isSelected =
                          identical(card, widget.selected) ||
                          (widget.selected != null &&
                              widget.selected!.name == card.name);
                      return _CoworkerPick(
                        card: card,
                        selected: isSelected,
                        amber: amber,
                        honey: honey,
                        onTap: () => widget.onSelected(card),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CoworkerPick extends StatelessWidget {
  const _CoworkerPick({
    required this.card,
    required this.selected,
    required this.amber,
    required this.honey,
    required this.onTap,
  });

  final CharacterCard card;
  final bool selected;
  final Color amber;
  final Color honey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final file = waifuCoworkerFace(context, card);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                amber.withValues(alpha: selected ? 0.45 : 0.16),
                AppColors.cardOf(context),
              ],
            ),
            border: Border.all(
              color: selected ? amber : amber.withValues(alpha: 0.35),
              width: selected ? 2.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: amber.withValues(alpha: 0.45),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                child: ClipOval(
                  child: CharacterPortrait(
                    size: 88,
                    file: file,
                    shrinkIfEmpty: false,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? honey : AppColors.textPrimary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
