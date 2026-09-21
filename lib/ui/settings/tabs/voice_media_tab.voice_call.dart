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

part of 'voice_media_tab.dart';

/// Voice Call settings sub-block of the Voice & Media tab: the Voice Call
/// Model selector (remote APIs only — local backends get an explanatory
/// line, since the per-turn swap is remote-only), Voice Buffer slider, Call
/// System Prompt editor, and Auto-send-transcription toggle. Lifted from
/// inside the STT card's `sttEnabled` conditional in the pre-split god file.
///
/// [_buildVoiceCallSection] returns a flat `List<Widget>` (not a single
/// Widget) so [_VoiceMediaSttSection._buildSttSection] can splice it back
/// into its own `sttEnabled` conditional spread with `...` at the exact
/// point these widgets sat before the split — preserving the single shared
/// Container/conditional the two sections still share (see the seam note
/// on _VoiceMediaSttSection).
extension _VoiceMediaCallSection on VoiceMediaTab {
  List<Widget> _buildVoiceCallSection(
    BuildContext context,
    StorageService storageService,
    LLMProvider llmProvider,
  ) {
    return [
      // Voice call model selector. Local backends are fully supported for
      // calls (maintainer direction 2026-08-14: "support Local kobold and
      // oMLX etc with just a warning that speed will be slower than with
      // using a remote hosted model") — the split is about who can SWAP:
      // • oMLX (and every OpenAI-compatible server, local or remote)
      //   carries the model as a request parameter, so the picker works
      //   there exactly as on a remote API — plus the speed warning.
      // • Managed KoboldCpp answers with the .gguf it has loaded; a per-
      //   call swap would restart the backend, so instead of the old
      //   decorative GGUF dropdown (picking one silently did nothing —
      //   chat_service_generation_request gates the swap on !isLocal) it
      //   gets the supportive warning + the Model Manager pointer.
      Builder(
        builder: (context) {
          final backend = llmProvider.activeBackend;
          if (backend == BackendType.kobold) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice Call Model',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Voice calls are fully supported on your local backend — '
                  'they answer with the model you have loaded.\n'
                  '⚠ A local model will be slower than a remote hosted '
                  'model. For snappier calls, load a smaller model in '
                  'Model Manager (KoboldCpp cannot swap models mid-call '
                  'without restarting).',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            );
          }
          final callModels = availableModels
              .map((m) => <String, dynamic>{'id': m.id, 'name': m.name})
              .toList();

          final recommended = callModels
              .where((m) {
                final lower = m['name']!.toLowerCase();
                return lower.contains('mini') ||
                    lower.contains('tiny') ||
                    lower.contains('1b') ||
                    lower.contains('3b') ||
                    lower.contains('4b') ||
                    lower.contains('flash') ||
                    lower.contains('haiku') ||
                    lower.contains('nano') ||
                    lower.contains('small');
              })
              .take(8)
              .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Voice Call Model',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.porchAmberOf(
                        context,
                      ).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      backend == BackendType.omlx ? 'oMLX' : 'API',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.porchAmberOf(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (callModels.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: storageService.sttSettings.callModelName.isEmpty
                      ? ''
                      : (callModels.any(
                              (m) =>
                                  m['id'] ==
                                  storageService.sttSettings.callModelName,
                            )
                            ? storageService.sttSettings.callModelName
                            : ''),
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceContainerOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    DropdownMenuItem<String>(
                      value: '',
                      child: Text(
                        'Same as main model',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    ...callModels.map((m) {
                      final name = m['name']!;
                      final isRec = recommended.any((r) => r['id'] == m['id']);
                      return DropdownMenuItem<String>(
                        value: m['id'],
                        child: Row(
                          children: [
                            if (isRec) ...[
                              Icon(
                                Icons.star,
                                size: 12,
                                color: AppColors.dialogue,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                name.length > 45
                                    ? '${name.substring(0, 42)}...'
                                    : name,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      storageService.sttSettings.setCallModelName(val);
                    }
                  },
                )
              else
                TextFormField(
                  initialValue: storageService.sttSettings.callModelName,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceContainerOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    hintText: 'Enter model ID or configure API first',
                    hintStyle: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 13,
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (val) =>
                      storageService.sttSettings.setCallModelName(val.trim()),
                ),
              const SizedBox(height: 4),
              Text(
                backend == BackendType.omlx
                    ? '💡 Use a smaller, faster model for voice calls.\n'
                          'Reasoning/thinking models add latency — not '
                          'recommended.\n'
                          '⚠ oMLX runs on this machine — calls will be '
                          'slower than a remote hosted model.'
                    : '💡 Use a smaller, faster model for voice calls.\n'
                          'Reasoning/thinking models add latency — not '
                          'recommended.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
              if (recommended.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '⭐ Recommended for voice calls:',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: recommended.map((m) {
                    final name = m['name']!;
                    final id = m['id']!;
                    final isSelected =
                        storageService.sttSettings.callModelName == id;
                    return ActionChip(
                      // theme-keep: download-ready status green (reused here
                      // as the "currently selected recommendation" highlight)
                      label: Text(
                        name.length > 30 ? '${name.substring(0, 27)}...' : name,
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected
                              ? AppColors.logReady
                              : AppColors.textSecondary(context),
                        ),
                      ),
                      backgroundColor: isSelected
                          ? AppColors.logReady.withValues(alpha: 0.15)
                          : AppColors.textTertiary(
                              context,
                            ).withValues(alpha: 0.05),
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.logReady.withValues(alpha: 0.4)
                            : AppColors.borderOf(
                                context,
                              ).withValues(alpha: 0.3),
                      ),
                      onPressed: () =>
                          storageService.sttSettings.setCallModelName(id),
                    );
                  }).toList(),
                ),
              ],
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      // Voice buffer size slider
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Voice Buffer',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
              Text(
                '${(dragCallBuffer ?? storageService.sttSettings.callBufferSentences.toDouble()).round()} sentences',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
          Slider(
            value:
                dragCallBuffer ??
                storageService.sttSettings.callBufferSentences.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: AppColors.porchAmberOf(context),
            onChanged: (val) => onDragCallBufferChanged(val),
            onChangeEnd: (val) {
              onDragCallBufferChanged(null);
              storageService.sttSettings.setCallBufferSentences(val.round());
            },
          ),
          Text(
            'Sentences to pre-generate before playback starts. '
            'Auto-expands if generation is slow.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      // Call system prompt
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Call System Prompt',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  storageService.sttSettings.setCallSystemPrompt(
                    'You are on a live voice call. Respond naturally as if speaking on the phone. '
                    'ALWAYS write in first person \u2014 never narrate in third person. '
                    'Keep responses concise: 1-3 sentences max. '
                    'No actions, no narration, no stage directions \u2014 just speak directly.',
                  );
                },
                icon: const Icon(Icons.restore, size: 14),
                label: const Text('Reset', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textTertiary(context),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 24),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          CallSystemPromptField(
            value: storageService.sttSettings.callSystemPrompt,
            onChanged: storageService.sttSettings.setCallSystemPrompt,
          ),
          const SizedBox(height: 4),
          Text(
            'Appended to the system prompt during voice calls to control response style.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.send,
                color: AppColors.porchAmberOf(context),
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                'Auto-send transcription',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          Switch(
            value: storageService.sttSettings.autoSendTranscription,
            onChanged: (val) =>
                storageService.sttSettings.setAutoSendTranscription(val),
          ),
        ],
      ),
      Text(
        'When enabled, transcribed text is sent automatically instead of being placed in the input field.',
        style: TextStyle(fontSize: 11, color: AppColors.textTertiary(context)),
      ),
    ];
  }
}

/// The Call System Prompt box. It edits a value that lives in StorageService,
/// and every keystroke notifies — which rebuilds this whole tab. A field whose
/// identity or `initialValue` is derived from that value is therefore torn
/// down mid-word (the old `key: ValueKey(prompt.hashCode)` did exactly that:
/// new key → `canUpdate` fails → new EditableText, new FocusNode, caret gone
/// after the first character). Owning the controller keeps ONE element alive
/// across those rebuilds while still following EXTERNAL changes — the Reset
/// button — through [didUpdateWidget].
class CallSystemPromptField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const CallSystemPromptField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<CallSystemPromptField> createState() => _CallSystemPromptFieldState();
}

class _CallSystemPromptFieldState extends State<CallSystemPromptField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(CallSystemPromptField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Echoing our own onChanged back into the controller would move the caret
    // to the end on every keystroke, so only adopt a value that differs from
    // what is already typed.
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: 4,
      minLines: 2,
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        hintText: 'Instructions appended during voice calls...',
        hintStyle: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 13,
        ),
      ),
      style: const TextStyle(fontSize: 12),
      onChanged: widget.onChanged,
    );
  }
}
