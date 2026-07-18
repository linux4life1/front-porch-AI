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
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/stt_service.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Full-screen voice call overlay.
///
/// Shows character avatar, call timer, waveform visualization,
/// status text, and mute/end buttons. Manages the continuous
/// listen → transcribe → send → TTS → listen call loop.
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
  late AnimationController _pulseController;
  late AnimationController _waveController;

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

    // Wire up the call loop
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCall();
    });
  }

  void _initCall() async {
    final sttService = Provider.of<SttService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);
    final ttsService = Provider.of<TtsService>(context, listen: false);

    // The session gates silence detection while TTS is audible/generating.
    sttService.call.attachTtsBusyProbe(
      () => ttsService.isSpeaking || ttsService.isGenerating,
    );

    // The turn loop. CallSession hands over one committed transcription per
    // user turn; everything after that — send, stream sentences into TTS,
    // and the SINGLE resume back to listening — happens here, strictly in
    // order. There is deliberately no isSpeaking polling anywhere.
    sttService.call.onTranscription = (text) async {
      final voiceKey = chatService.activeCharacter?.ttsVoice;

      // Buffer sentences so none are lost between sendMessage starting to
      // stream and speakStreaming subscribing (broadcast streams drop
      // events with no listener).
      final sentenceController = StreamController<String>();
      final sub = chatService.sentenceStream.listen((sentence) {
        if (sentence == '__DONE__') {
          if (!sentenceController.isClosed) sentenceController.close();
          return;
        }
        sentenceController.add(sentence);
        // First sentence arriving = the reply is being spoken.
        if (sttService.call.status == CallStatus.thinking) {
          sttService.call.notifySpeaking();
        }
      });

      chatService.sendMessage(text);

      try {
        await ttsService.speakStreaming(
          sentenceController.stream,
          voiceKey: voiceKey,
        );
      } finally {
        await sub.cancel();
        if (!sentenceController.isClosed) {
          await sentenceController.close();
        }
        // The one and only resume point: TTS is genuinely finished (or
        // failed) — CallSession ignores this if the call ended meanwhile.
        await sttService.call.resumeAfterTts();
      }
    };

    // Enable call mode (disables reasoning for lower latency)
    chatService.callMode = true;

    // Start the call (begins listening)
    sttService.call.start();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _statusText(CallStatus status) {
    switch (status) {
      case CallStatus.listening:
        return 'Listening...';
      case CallStatus.transcribing:
        return 'Transcribing...';
      case CallStatus.thinking:
        return 'Thinking...';
      case CallStatus.speaking:
        return 'Speaking...';
      case CallStatus.idle:
        return 'Calibrating...';
    }
  }

  IconData _statusIcon(CallStatus status) {
    switch (status) {
      case CallStatus.listening:
        return Icons.mic;
      case CallStatus.transcribing:
        return Icons.text_fields;
      case CallStatus.thinking:
        return Icons.psychology;
      case CallStatus.speaking:
        return Icons.volume_up;
      case CallStatus.idle:
        return Icons.pause;
    }
  }

  Color _statusColor(CallStatus status) {
    switch (status) {
      case CallStatus.listening:
        return Colors.greenAccent;
      case CallStatus.transcribing:
        return Colors.blueAccent;
      case CallStatus.thinking:
        return Colors.amberAccent;
      case CallStatus.speaking:
        return Colors.purpleAccent;
      case CallStatus.idle:
        return Colors.white38;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SttService>(
      builder: (context, sttService, _) {
        final status = sttService.call.status;
        final amplitude = sttService.currentAmplitude;
        final duration = sttService.call.duration;
        final isMuted = sttService.call.isMuted;
        final lastText = sttService.lastTranscription;

        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0A0E1A).withValues(alpha: 0.97),
                  const Color(0xFF111827).withValues(alpha: 0.98),
                  const Color(0xFF1A1040).withValues(alpha: 0.97),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  // ── Call header ──
                  Text(
                    '📞 Voice Call',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                      fontFamily: 'monospace',
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Character Avatar ──
                  _buildAvatar(status, amplitude),

                  const SizedBox(height: 20),

                  // ── Character Name ──
                  Text(
                    widget.character.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Status indicator ──
                  _buildStatusChip(status),

                  const Spacer(flex: 1),

                  // ── Waveform ──
                  _buildWaveform(amplitude, status),

                  const SizedBox(height: 24),

                  // ── Last transcription ──
                  if (lastText != null && lastText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Text(
                          '"$lastText"',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),

                  const Spacer(flex: 2),

                  // ── Control buttons ──
                  _buildControls(sttService, isMuted),

                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(CallStatus status, double amplitude) {
    final isActive =
        status == CallStatus.listening || status == CallStatus.speaking;
    final ringColor = _statusColor(status);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulseScale = isActive
            ? 1.0 + (_pulseController.value * 0.04) + (amplitude * 0.08)
            : 1.0;

        return Transform.scale(
          scale: pulseScale,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: ringColor.withValues(alpha: isActive ? 0.3 : 0.1),
                  blurRadius: isActive ? 40 + amplitude * 20 : 20,
                  spreadRadius: isActive ? 4 + amplitude * 8 : 2,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    ringColor.withValues(alpha: 0.6),
                    ringColor.withValues(alpha: 0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: CircleAvatar(
                radius: 76,
                backgroundColor: const Color(0xFF1F2937),
                backgroundImage: widget.character.imagePath != null
                    ? FileImage(File(widget.character.imagePath!))
                    : null,
                child: widget.character.imagePath == null
                    ? Text(
                        widget.character.name.isNotEmpty
                            ? widget.character.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white54,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(CallStatus status) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(status),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _statusColor(status).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _statusColor(status).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_statusIcon(status), size: 16, color: _statusColor(status)),
            const SizedBox(width: 8),
            Text(
              _statusText(status),
              style: TextStyle(
                color: _statusColor(status),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveform(double amplitude, CallStatus status) {
    final isListening = status == CallStatus.listening;
    const barCount = 9;

    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, _) {
        return SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(barCount, (i) {
              // Create wave-like pattern
              final phase =
                  (i / barCount * 2 * pi) + (_waveController.value * 2 * pi);
              final waveHeight = isListening
                  ? 0.3 + (sin(phase) * 0.3 + 0.3) * amplitude
                  : (status == CallStatus.speaking)
                  ? 0.2 + sin(phase) * 0.3
                  : 0.15;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 4,
                  height: 8 + (waveHeight * 52),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        _statusColor(status).withValues(alpha: 0.8),
                        _statusColor(status).withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildControls(SttService sttService, bool isMuted) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── Mute button ──
        _buildControlButton(
          icon: isMuted ? Icons.mic_off : Icons.mic,
          label: isMuted ? 'Unmute' : 'Mute',
          color: isMuted ? Colors.orangeAccent : Colors.white70,
          backgroundColor: isMuted
              ? Colors.orangeAccent.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.08),
          onTap: () => sttService.call.toggleMute(),
        ),
        const SizedBox(width: 32),

        // ── Stop recording / send button (only when listening) ──
        if (sttService.call.status == CallStatus.listening &&
            sttService.isRecording)
          _buildControlButton(
            icon: Icons.send,
            label: 'Send',
            color: AppColors.formMasterAccent,
            backgroundColor: AppColors.formMasterAccent.withValues(alpha: 0.15),
            size: 64,
            onTap: () => sttService.call.sendNow(),
          ),
        if (sttService.call.status == CallStatus.listening &&
            sttService.isRecording)
          const SizedBox(width: 32),

        // ── End call button ──
        _buildControlButton(
          icon: Icons.call_end,
          label: 'End',
          color: Colors.redAccent,
          backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
          onTap: () async {
            final chatService = Provider.of<ChatService>(
              context,
              listen: false,
            );
            final ttsService = Provider.of<TtsService>(context, listen: false);
            await ttsService.stop(); // immediately stop any ongoing playback
            await sttService.call.end();
            chatService.callMode = false;
            widget.onEndCall();
          },
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color backgroundColor,
    required VoidCallback onTap,
    double size = 56,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor,
              border: Border.all(
                color: color.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: color, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
