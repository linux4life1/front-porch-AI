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
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/models/chat_generation_settings.dart';
import 'package:front_porch_ai/ui/widgets/slider_with_input.dart';

class ChatSettingsDialog extends StatefulWidget {
  const ChatSettingsDialog({super.key});

  @override
  State<ChatSettingsDialog> createState() => _ChatSettingsDialogState();
}

class _ChatSettingsDialogState extends State<ChatSettingsDialog> {
  final TextEditingController _stopSequenceController = TextEditingController();
  late final TextEditingController _bannedPhrasesController;
  late ChatGenerationSettings _gen;
  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      final chatService = Provider.of<ChatService>(context, listen: false);
      final storage = Provider.of<StorageService>(context, listen: false);
      _gen = chatService.sessionGenSettings;
      _bannedPhrasesController = TextEditingController(
        text: _gen.resolveBannedPhrases(storage).join('\n'),
      );
      _initialised = true;
    }
  }

  @override
  void dispose() {
    _stopSequenceController.dispose();
    _bannedPhrasesController.dispose();
    super.dispose();
  }

  /// Write the mutated [_gen] back to ChatService (which persists to DB).
  void _save() {
    final chatService = Provider.of<ChatService>(context, listen: false);
    chatService.sessionGenSettings = _gen;
  }

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final llmProvider = Provider.of<LLMProvider>(context);
    final isRemote = !llmProvider.isLocal;
    final hasOverrides = _gen.hasOverrides;

    return Dialog(
        backgroundColor: const Color(0xFF1F2937),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Row(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                       const Text('Chat Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                       if (hasOverrides) ...[
                         const SizedBox(width: 8),
                         Container(
                           padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                           decoration: BoxDecoration(
                             color: Colors.amber.withValues(alpha: 0.15),
                             borderRadius: BorderRadius.circular(4),
                             border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                           ),
                           child: const Text('Custom', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                         ),
                       ],
                     ],
                   ),
                   Row(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                       if (hasOverrides)
                         Tooltip(
                           message: 'Reset to global defaults',
                           child: IconButton(
                             icon: const Icon(Icons.restart_alt, color: Colors.amber, size: 20),
                             onPressed: () {
                               setState(() {
                                 _gen = ChatGenerationSettings();
                                 _bannedPhrasesController.text = storage.bannedPhrases.join('\n');
                               });
                               _save();
                             },
                           ),
                         ),
                       IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(context)),
                     ],
                   ),
                 ],
               ),
               if (hasOverrides)
                 Padding(
                   padding: const EdgeInsets.only(bottom: 8),
                   child: Text(
                     'This chat has custom generation settings that override global defaults.',
                     style: TextStyle(color: Colors.amber.withValues(alpha: 0.7), fontSize: 11),
                   ),
                 ),
               const SizedBox(height: 8),

               Expanded(
                 child: SingleChildScrollView(
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       // Reasoning toggle (only for Remote API)
                       if (isRemote) ...[
                         const Text('Reasoning', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                         const SizedBox(height: 8),
                         Row(
                           children: [
                             const Text('Request Reasoning', style: TextStyle(color: Colors.white)),
                             const Spacer(),
                             Switch(
                               value: _gen.resolveReasoningEnabled(storage),
                               onChanged: (val) {
                                 setState(() => _gen.reasoningEnabled = val);
                                 _save();
                               },
                               activeTrackColor: Colors.blueAccent,
                             ),
                           ],
                         ),
                         if (_gen.resolveReasoningEnabled(storage))
                           Padding(
                             padding: const EdgeInsets.only(bottom: 8),
                             child: Row(
                               children: [
                                 const Text('Effort Level', style: TextStyle(color: Colors.white70)),
                                 const Spacer(),
                                 Container(
                                   padding: const EdgeInsets.symmetric(horizontal: 12),
                                   decoration: BoxDecoration(
                                     color: const Color(0xFF374151),
                                     borderRadius: BorderRadius.circular(8),
                                   ),
                                   child: DropdownButtonHideUnderline(
                                     child: DropdownButton<String>(
                                       value: _gen.resolveReasoningEffort(storage),
                                       dropdownColor: const Color(0xFF374151),
                                       style: const TextStyle(color: Colors.white),
                                       items: const [
                                         DropdownMenuItem(value: 'low', child: Text('Low')),
                                         DropdownMenuItem(value: 'medium', child: Text('Medium')),
                                         DropdownMenuItem(value: 'high', child: Text('High')),
                                       ],
                                       onChanged: (val) {
                                         if (val != null) {
                                           setState(() => _gen.reasoningEffort = val);
                                           _save();
                                         }
                                       },
                                     ),
                                   ),
                                 ),
                               ],
                             ),
                           ),
                         if (!_gen.resolveReasoningEnabled(storage))
                           Padding(
                             padding: const EdgeInsets.only(bottom: 8),
                             child: Text(
                               'Enable to request thinking/reasoning from compatible models',
                               style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                             ),
                           ),
                         const SizedBox(height: 8),
                         const Divider(color: Colors.white10),
                         const SizedBox(height: 8),
                       ],

                       // Generation
                       const Text('Generation', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                       const SizedBox(height: 8),
                        SliderWithInput(
                          label: 'Temperature',
                          value: _gen.resolveTemperature(storage),
                          min: 0.0,
                          max: 2.0,
                          divisions: 20,
                          tooltip: 'Controls randomness. Low = predictable and focused. High = creative and surprising. 0.7 is a good default.',
                          context: context,
                          onChanged: (val) {
                            setState(() => _gen.temperature = val);
                            _save();
                          },
                        ),
                        SliderWithInput(
                          label: 'Min-P',
                          value: _gen.resolveMinP(storage),
                          min: 0.0,
                          max: 1.0,
                          divisions: 100,
                          tooltip: 'Filters out unlikely words. Higher = only the most probable words are kept. Start around 0.05–0.1.',
                          context: context,
                          onChanged: (val) {
                            setState(() => _gen.minP = val);
                            _save();
                          },
                        ),
                        SliderWithInput(
                          label: 'Repeat Penalty',
                          value: _gen.resolveRepeatPenalty(storage),
                          min: 1.0,
                          max: 3.0,
                          divisions: 200,
                          tooltip: 'Discourages the AI from repeating the same words. Higher = less repetition. 1.1 is a safe default.',
                          context: context,
                          onChanged: (val) {
                            setState(() => _gen.repeatPenalty = val);
                            _save();
                          },
                        ),
                        SliderWithInput(
                          label: 'Rep Pen Tokens',
                          value: _gen.resolveRepeatPenaltyTokens(storage).toDouble(),
                          min: 0,
                          max: 512,
                          divisions: 512,
                          isInteger: true,
                          tooltip: 'How far back the AI checks for repetition (in tokens). Higher = checks more of the conversation history.',
                          context: context,
                          onChanged: (val) {
                            setState(() => _gen.repeatPenaltyTokens = val.toInt());
                            _save();
                          },
                        ),
                        SliderWithInput(
                          label: 'XTC Threshold',
                          value: _gen.resolveXtcThreshold(storage),
                          min: 0.0,
                          max: 0.5,
                          divisions: 50,
                          tooltip: 'Exclude Top Choices — removes the most obvious/cliché word choices. Lower = stronger effect. Try 0.1 for more creative writing.',
                          context: context,
                          onChanged: (val) {
                            setState(() => _gen.xtcThreshold = val);
                            _save();
                          },
                        ),
                        SliderWithInput(
                          label: 'XTC Probability',
                          value: _gen.resolveXtcProbability(storage),
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          tooltip: 'How often XTC activates. 0 = never, 1 = always. Try 0.5 for a balance between creativity and coherence.',
                          context: context,
                          onChanged: (val) {
                            setState(() => _gen.xtcProbability = val);
                            _save();
                          },
                        ),
                        SliderWithInput(
                          label: 'Max Output Tokens',
                          value: _gen.resolveMaxLength(storage).toDouble(),
                          min: 16,
                          max: 16384,
                          isInteger: true,
                          tooltip: 'Maximum number of tokens the AI can write in one response. Thinking models need higher values since reasoning tokens count toward this limit.',
                          context: context,
                          onChanged: (val) {
                            setState(() => _gen.maxLength = val.toInt());
                            _save();
                          },
                        ),
                        SliderWithInput(
                          label: 'Min Output Tokens',
                          value: _gen.resolveMinLength(storage).toDouble(),
                          min: 0,
                          max: 512,
                          divisions: 512,
                          isInteger: true,
                          tooltip: 'Minimum tokens the AI must write before it can stop. Increase for longer responses.',
                          context: context,
                          onChanged: (val) {
                            setState(() => _gen.minLength = val.toInt());
                            _save();
                          },
                        ),
                        IgnorePointer(
                          ignoring: storage.activeKcppsPath != null && storage.activeKcppsPath!.isNotEmpty,
                          child: Opacity(
                            opacity: storage.activeKcppsPath != null && storage.activeKcppsPath!.isNotEmpty ? 0.5 : 1.0,
                            child: Tooltip(
                              message: storage.activeKcppsPath != null && storage.activeKcppsPath!.isNotEmpty
                                  ? 'Context size is controlled by the active .kcpps preset and cannot be edited here.'
                                  : '',
                              child: SliderWithInput(
                                label: 'Context Size',
                                value: _gen.resolveContextSize(storage).toDouble().clamp(512, isRemote ? 500000 : 131072),
                                min: 512,
                                max: isRemote ? 500000.0 : 131072.0,
                                isInteger: true,
                                divisions: ((isRemote ? 500000.0 : 131072.0) - 512) ~/ 512,
                                context: context,
                                onChanged: (val) {
                                  setState(() => _gen.contextSize = val.toInt());
                                  _save();
                                },
                              ),
                            ),
                          ),
                        ),

                       const SizedBox(height: 16),
                       Row(
                         children: [
                           const Text('Dynamic Temperature', style: TextStyle(color: Colors.white)),
                           Tooltip(
                             message: 'Varies temperature randomly within a range each generation for more varied outputs.',
                             child: const Padding(
                               padding: EdgeInsets.only(left: 4),
                               child: Icon(Icons.info_outline, size: 16, color: Colors.white38),
                             ),
                           ),
                           const Spacer(),
                           Switch(
                             value: _gen.resolveDynamicTempEnabled(storage),
                             onChanged: (val) {
                               setState(() => _gen.dynamicTempEnabled = val);
                               _save();
                             },
                             activeTrackColor: Colors.blueAccent,
                           ),
                         ],
                       ),
                        if (_gen.resolveDynamicTempEnabled(storage))
                          SliderWithInput(
                            label: 'Dynatemp Range',
                            value: _gen.resolveDynamicTempRange(storage),
                            min: 0.0,
                            max: 2.0,
                            divisions: 20,
                            tooltip: 'How much the temperature can vary around the base temperature.',
                            context: context,
                            onChanged: (val) {
                              setState(() => _gen.dynamicTempRange = val);
                              _save();
                            },
                          ),

                        const SizedBox(height: 24),
                        const Text('Stop Sequences', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                        const SizedBox(height: 8),
                         Container(
                           decoration: BoxDecoration(
                             color: const Color(0xFF374151),
                             borderRadius: BorderRadius.circular(8),
                           ),
                           child: Column(
                             children: [
                               Padding(
                                 padding: const EdgeInsets.symmetric(horizontal: 12),
                                 child: Row(
                                   children: [
                                     Expanded(
                                       child: TextField(
                                         controller: _stopSequenceController,
                                         style: const TextStyle(color: Colors.white),
                                         decoration: const InputDecoration(
                                           hintText: 'Add stop sequence...',
                                           hintStyle: TextStyle(color: Colors.white38),
                                           border: InputBorder.none,
                                         ),
                                         onSubmitted: (val) {
                                            if (val.isNotEmpty) {
                                              setState(() {
                                                final resolved = _gen.resolveStopSequences(storage);
                                                _gen.stopSequences = [...resolved, val];
                                              });
                                              _stopSequenceController.clear();
                                              _save();
                                            }
                                         },
                                       ),
                                     ),
                                     IconButton(
                                       icon: const Icon(Icons.add_circle, color: Colors.blueAccent),
                                       onPressed: () {
                                         if (_stopSequenceController.text.isNotEmpty) {
                                           setState(() {
                                             final resolved = _gen.resolveStopSequences(storage);
                                             _gen.stopSequences = [...resolved, _stopSequenceController.text];
                                           });
                                           _stopSequenceController.clear();
                                           _save();
                                         }
                                       },
                                     ),
                                   ],
                                 ),
                               ),
                               const Divider(height: 1, color: Colors.white10),
                               ..._gen.resolveStopSequences(storage).map((seq) => ListTile(
                                 title: Text(seq.replaceAll('\n', '\\n'), style: const TextStyle(color: Colors.white)),
                                 trailing: IconButton(
                                   icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                   onPressed: () {
                                     setState(() {
                                       final resolved = _gen.resolveStopSequences(storage).toList();
                                       resolved.remove(seq);
                                       _gen.stopSequences = resolved;
                                     });
                                     _save();
                                   },
                                 ),
                                 dense: true,
                               )),
                             ],
                           ),
                         ),

                         // ── Banned Phrases (Anti-Slop) — local KoboldCpp only ──
                         if (!isRemote) ...[
                         const SizedBox(height: 24),
                         Row(
                           children: [
                             const Text('Banned Phrases', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                             const SizedBox(width: 6),
                             Tooltip(
                               message: 'If any of these phrases appear during generation, the model backtracks and regenerates without them.',
                               child: const Icon(Icons.info_outline, size: 16, color: Colors.white38),
                             ),
                           ],
                         ),
                         const SizedBox(height: 4),
                         Text(
                           'One phrase per line',
                           style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                         ),
                         const SizedBox(height: 8),
                         Container(
                           decoration: BoxDecoration(
                             color: const Color(0xFF374151),
                             borderRadius: BorderRadius.circular(8),
                           ),
                           padding: const EdgeInsets.all(8.0),
                           child: TextField(
                             controller: _bannedPhrasesController,
                             maxLines: 5,
                             minLines: 2,
                             style: const TextStyle(color: Colors.white, fontSize: 13),
                             decoration: const InputDecoration(
                               hintText: 'shivers down\na cold shiver\nher eyes sparkled',
                               hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                               border: InputBorder.none,
                               contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                             ),
                             onChanged: (val) {
                               final phrases = val.split('\n').where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toList();
                               _gen.bannedPhrases = phrases;
                               _save();
                             },
                           ),
                         ),
                         if (_gen.resolveBannedPhrases(storage).isNotEmpty)
                           Padding(
                             padding: const EdgeInsets.only(top: 6),
                             child: Text(
                               '${_gen.resolveBannedPhrases(storage).length} phrase${_gen.resolveBannedPhrases(storage).length == 1 ? '' : 's'} banned',
                               style: TextStyle(color: Colors.amber.shade300, fontSize: 11),
                             ),
                           ),
                         ],


                     ],
                   ),
                 ),
               ),
            ],
          ),
        ),
    );
  }

}
