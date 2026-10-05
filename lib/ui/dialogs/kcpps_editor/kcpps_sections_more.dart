// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'kcpps_editor_controller.dart';
import 'kcpps_editor_style.dart';

String _gb(int mb) => '${(mb / 1024).toStringAsFixed(1)} GB';

/// Smart cache: the suggestion, why, and the number of slots.
class KcppsSmartCacheSection extends StatefulWidget {
  const KcppsSmartCacheSection({super.key, required this.c});

  final KcppsEditorController c;

  @override
  State<KcppsSmartCacheSection> createState() => _KcppsSmartCacheState();
}

class _KcppsSmartCacheState extends State<KcppsSmartCacheSection> {
  final _slots = TextEditingController();
  String? _problem;

  KcppsEditorController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _slots.text = '${c.draft.slots}';
  }

  @override
  void didUpdateWidget(KcppsSmartCacheSection old) {
    super.didUpdateWidget(old);
    if (_problem == null && int.tryParse(_slots.text) != c.draft.slots) {
      _slots.text = '${c.draft.slots}';
    }
  }

  @override
  void dispose() {
    _slots.dispose();
    super.dispose();
  }

  void _typed(String text) {
    final n = int.tryParse(text);
    setState(
      () => _problem = n == null || n > 20 ? 'From 0 to 20 slots.' : null,
    );
    if (_problem == null) c.edit((d) => d.copyWith(slots: n));
  }

  String _why(({int slots, SmartCacheLimit limit}) s) {
    final free = c.machine?.systemMb;
    final load = c.view?.load;
    final need = load == null || c.machine == null
        ? null
        : koboldModelSystemMb(load, c.machine!);
    final room = free == null || need == null
        ? ''
        : 'This computer has ${_gb(free)} of memory free, and the model '
              'already needs ${_gb(need)} of it';
    return switch (s.limit) {
      SmartCacheLimit.noRoom =>
        room.isEmpty
            ? 'This computer has no memory to spare for them.'
            : '$room, so slots would slow it down.',
      SmartCacheLimit.memory =>
        room.isEmpty ? 'That is what fits.' : '$room: that is what fits.',
      SmartCacheLimit.promptKinds =>
        c.recurrent
            ? "KoboldCpp's own number for this model: one of them also "
                  'brings a regenerated reply back quickly.'
            : 'One for the chat, one for the judges, and one spare.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.slateFaintOf(context);
    final muted = AppColors.slateMutedOf(context);
    if (c.slidingWindowOn) {
      return KeSection(
        title: 'Switching between chats (smart cache)',
        gap: 10,
        children: [
          Text(
            'Smart cache needs fast forward, which sliding window turns off.',
            style: keText(context, size: 13, color: muted, height: 1.45),
          ),
        ],
      );
    }
    final s = c.suggestedSlots;
    final slotMb = c.slotMb;
    final made = c.slotsMade;
    final hint = made != c.draft.slots
        ? 'KoboldCpp makes $made for this model'
        : c.recurrent && made >= 3
        ? 'KoboldCpp keeps one of them for this model by itself'
        : null;
    return KeSection(
      title: 'Switching between chats (smart cache)',
      gap: 10,
      children: [
        Text.rich(
          TextSpan(
            children: [
              if (s != null) ...[
                const TextSpan(text: 'Suggested: '),
                TextSpan(
                  text: s.slots == 0
                      ? 'no slots.'
                      : '${s.slots} ${s.slots == 1 ? 'slot' : 'slots'}.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.slateInkOf(context),
                  ),
                ),
                TextSpan(text: ' ${_why(s)} '),
              ],
              TextSpan(
                text:
                    'With room, each slot${slotMb == null ? '' : ' (up to ${_gb(slotMb)})'} '
                    'brings a chat back in under a second instead of reading '
                    'it again.',
              ),
            ],
          ),
          style: keText(context, size: 13, color: muted, height: 1.45),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const KeLabel('Slots', size: 13),
            KeBox(
              controller: _slots,
              keyName: 'kcpps-slots',
              width: 72,
              number: true,
              error: _problem != null,
              semanticLabel: 'Smart cache slots',
              onChanged: _typed,
            ),
            if (_problem ?? hint case final note?)
              Text(
                note,
                style: keText(
                  context,
                  size: 12,
                  color: _problem != null
                      ? AppColors.alertRedOf(context)
                      : faint,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Extras: the vision file, a draft model, and what is kept as written.
class KcppsExtrasSection extends StatelessWidget {
  const KcppsExtrasSection({super.key, required this.c});

  final KcppsEditorController c;

  Future<String?> _pick() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['gguf'],
    );
    return result?.files.single.path;
  }

  Widget _row(
    BuildContext context,
    String label,
    String path,
    ValueChanged<String> set,
  ) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: keText(
            context,
            size: 13,
            color: AppColors.slateMutedOf(context),
          ),
        ),
      ),
      if (path.isNotEmpty) ...[
        KeButton(
          'Remove',
          height: 36,
          padding: 12,
          fontSize: 13,
          onPressed: () => set(''),
        ),
        const SizedBox(width: 6),
      ],
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: KeButton(
          '${path.isEmpty ? 'None' : p.basename(path)} · Choose…',
          height: 36,
          padding: 12,
          fontSize: 13,
          onPressed: () async {
            final picked = await _pick();
            if (picked != null) set(picked);
          },
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final kept = c.unmanaged;
    return KeSection(
      title: 'Extras',
      gap: 10,
      children: [
        _row(
          context,
          'Vision file',
          c.draft.mmprojPath,
          (v) => c.edit((d) => d.copyWith(mmprojPath: v)),
        ),
        if (c.draft.mmprojPath.isNotEmpty)
          KeCheck(
            value: c.draft.mmprojOnCpu,
            label:
                'Keep the vision file in system memory (more room on the card)',
            onChanged: (v) => c.edit((d) => d.copyWith(mmprojOnCpu: v)),
          ),
        _row(
          context,
          'Draft model (guesses ahead to write faster)',
          c.draft.draftModelPath,
          c.setDraftModel,
        ),
        // Offered for a model whose file has draft heads, or a preset that
        // already turned them on.
        if ((c.info?.draftHeads ?? 0) > 0 || c.draft.useMtp)
          KeCheck(
            value: c.draft.useMtp,
            label:
                "Use the model's own draft heads (guesses ahead to write "
                'faster)',
            onChanged: (v) => c.edit((d) => d.copyWith(useMtp: v)),
          ),
        if (c.draft.draftModelPath.isNotEmpty || c.draft.useMtp)
          KcppsDraftAmount(key: ValueKey('draft-amount ${c.path}'), c: c),
        if (kept.isNotEmpty)
          Text(
            'Kept as written: ${kept.length} '
            '${kept.length == 1 ? 'setting' : 'settings'} this app does not '
            'manage (${kept.take(4).join(', ')}${kept.length > 4 ? ', …' : ''}).',
            style: keText(
              context,
              size: 12,
              color: AppColors.slateFaintOf(context),
            ),
          ),
      ],
    );
  }
}

/// The preset in a few plain sentences.
class KcppsPlainWords extends StatelessWidget {
  const KcppsPlainWords({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
    decoration: BoxDecoration(
      color: AppColors.sunkenSurfaceOf(context),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'IN PLAIN WORDS',
          style: keText(
            context,
            size: 12,
            weight: FontWeight.w700,
            spacing: 0.72,
            color: AppColors.slateFaintOf(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          text,
          key: const ValueKey('kcpps-plain-words'),
          style: keText(context, size: 14, height: 1.5),
        ),
      ],
    ),
  );
}

/// Tokens guessed each step. Empty leaves it to KoboldCpp (4).
class KcppsDraftAmount extends StatefulWidget {
  const KcppsDraftAmount({super.key, required this.c});

  final KcppsEditorController c;

  @override
  State<KcppsDraftAmount> createState() => _KcppsDraftAmountState();
}

class _KcppsDraftAmountState extends State<KcppsDraftAmount> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.c.draft.draftAmount?.toString() ?? '',
  );
  String? _problem;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _typed(String text) {
    final value = int.tryParse(text.trim());
    final empty = text.trim().isEmpty;
    setState(
      () => _problem = empty || (value != null && value >= 1 && value <= 16)
          ? null
          : 'A whole number from 1 to 16.',
    );
    if (_problem != null) return;
    widget.c.edit(
      (d) => d.copyWith(draftAmount: value, clearDraftAmount: empty),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const KeLabel('Tokens guessed each step', size: 13),
      KeBox(
        controller: _amount,
        keyName: 'kcpps-draft-amount',
        width: 72,
        number: true,
        error: _problem != null,
        semanticLabel: 'Tokens guessed each step',
        onChanged: _typed,
      ),
      Text(
        _problem ?? 'Empty: KoboldCpp guesses 4.',
        style: keText(
          context,
          size: 12,
          color: _problem != null
              ? AppColors.alertRedOf(context)
              : AppColors.slateFaintOf(context),
        ),
      ),
    ],
  );
}
