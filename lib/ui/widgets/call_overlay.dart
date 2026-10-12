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
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/call_overlay/call_overlay.dart';

/// Full-screen voice call overlay (warm-porch rework, 2026-08-14).
///
/// **The overlay's presence in the tree IS the call.** Every teardown path —
/// the End button, a TTS error hiding the overlay, a chat switch, the page
/// being disposed — removes this widget, and [dispose] runs the ONE
/// idempotent teardown: transcription callback detached, TTS stopped, call
/// session ended (mic released), `callMode` cleared. The old design spread
/// teardown across three owners, and the paths that only hid the overlay
/// left a headless call running: mic hot, transcriptions still auto-sending,
/// the call prompt still latched onto the text chat.
///
/// Also owns the turn loop: [CallSession] hands over one committed
/// transcription per user turn; everything after that — send, stream
/// sentences into TTS, and the SINGLE resume back to listening — happens
/// here, strictly in order. No isSpeaking polling anywhere.
class CallOverlay extends StatefulWidget {
  final CharacterCard character;
  final VoidCallback onEndCall;

  const CallOverlay({
    super.key,
    required this.character,
    required this.onEndCall,
  });

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _waveController;

  // Captured in _initCall so dispose can tear down without a context (the
  // element is already deactivated when dispose runs).
  SttService? _stt;
  TtsService? _tts;
  ChatService? _chat;
  bool _torndown = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initCall();
    });
  }

  void _initCall() {
    final stt = _stt = Provider.of<SttService>(context, listen: false);
    final chat = _chat = Provider.of<ChatService>(context, listen: false);
    final tts = _tts = Provider.of<TtsService>(context, listen: false);

    // The session gates silence detection while TTS is audible/generating.
    stt.call.attachTtsBusyProbe(() => tts.isSpeaking || tts.isGenerating);

    // The turn loop. Buffer sentences so none are lost between sendMessage
    // starting to stream and speakStreaming subscribing (broadcast streams
    // drop events with no listener).
    stt.call.onTranscription = (text) async {
      if (_torndown) return;
      final voiceKey = chat.activeCharacter?.ttsVoice;
      final sentenceController = StreamController<String>();
      final sub = chat.sentenceStream.listen((sentence) {
        if (sentence == '__DONE__') {
          if (!sentenceController.isClosed) sentenceController.close();
          return;
        }
        sentenceController.add(sentence);
        // First sentence arriving = the reply is being spoken.
        if (stt.call.status == CallStatus.thinking) {
          stt.call.notifySpeaking();
        }
      });

      chat.sendMessage(text);

      try {
        await tts.speakStreaming(sentenceController.stream, voiceKey: voiceKey);
      } finally {
        await sub.cancel();
        if (!sentenceController.isClosed) await sentenceController.close();
        // The one and only resume point: TTS is genuinely finished (or
        // failed) — CallSession ignores this if the call ended meanwhile.
        await stt.call.resumeAfterTts();
      }
    };

    chat.callMode = true; // disables reasoning; enables the call prompt
    stt.call.start();
  }

  /// The single teardown, idempotent so the End button (snappy stop) and
  /// [dispose] (the guarantee) can both call it.
  void _teardown() {
    if (_torndown) return;
    _torndown = true;
    final stt = _stt;
    final tts = _tts;
    final chat = _chat;
    // Plain field write, no notify — synchronous so a late transcription
    // has nowhere to send even during the microtask gap below.
    stt?.call.onTranscription = null;
    // Everything else notifies listeners, which is illegal while the tree
    // is locked (dispose runs during unmount). One microtask defers past
    // the lock; the End button path reaches here the same way and a
    // microtask is imperceptible.
    scheduleMicrotask(() {
      unawaited(tts?.stop());
      unawaited(stt?.call.end());
      chat?.callMode = false; // also releases a parked call-model swap
    });
  }

  @override
  void dispose() {
    _teardown();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<SttService, TtsService, ChatService>(
      builder: (context, stt, tts, chat, _) {
        final status = stt.call.status;
        final amplitude = stt.currentAmplitude;
        final bg = AppColors.backgroundOf(context);
        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  bg.withValues(alpha: 0.98),
                  AppColors.surfaceOf(context).withValues(alpha: 0.98),
                  Color.lerp(
                    bg,
                    AppColors.porchAmberOf(context),
                    0.10,
                  )!.withValues(alpha: 0.98),
                ],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  // Short windows shrink the avatar instead of overflowing —
                  // a resized desktop window must never clip the End button.
                  final avatarSize = min(160.0, box.maxHeight * 0.22);
                  return Column(
                    children: [
                      const SizedBox(height: 20),
                      Text(
                        'VOICE CALL',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 12,
                          letterSpacing: 3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatDuration(stt.call.duration),
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w300,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Spacer(flex: 2),
                      CallAvatar(
                        pulse: _pulseController,
                        character: widget.character,
                        status: status,
                        amp: amplitude,
                        size: avatarSize,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        widget.character.name,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      CallRealismStrip(chat: chat),
                      const SizedBox(height: 12),
                      CallStatusChip(status: status),
                      const Spacer(flex: 1),
                      CallWaveform(
                        wave: _waveController,
                        amp: amplitude,
                        status: status,
                      ),
                      const SizedBox(height: 16),
                      CallCaptionArea(stt: stt, tts: tts),
                      const Spacer(flex: 2),
                      CallControls(
                        stt: stt,
                        onEnd: () {
                          _teardown(); // snappy: mic + TTS stop NOW, not next frame
                          widget.onEndCall();
                        },
                      ),
                      const SizedBox(height: 32),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
