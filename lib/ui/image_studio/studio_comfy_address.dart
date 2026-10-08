// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/comfy_url_probe.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The ComfyUI address on the stove: a field that saves when it is submitted
/// or left (never per keystroke), a Test button, and a line that says whether
/// ComfyUI answers there. A typed address always wins; clearing it lets Front
/// Porch find ComfyUI again. When ComfyUI answers somewhere else, [offer]
/// says where and "Use this" switches to it.
class StudioComfyAddress extends StatefulWidget {
  const StudioComfyAddress({
    super.key,
    required this.url,
    required this.explicit,
    required this.onSave,
    this.offer,
    this.answers = comfyAnswersAt,
  });

  /// The saved address.
  final String url;

  /// The person gave it (else it was found or is the default).
  final bool explicit;

  /// Saves a checked address, or '' to find ComfyUI again.
  final Future<void> Function(String url) onSave;

  /// Where ComfyUI answers, when that is not [url].
  final String? offer;

  /// Whether ComfyUI answers at an address; for tests.
  final Future<bool> Function(String url) answers;

  @override
  State<StudioComfyAddress> createState() => _StudioComfyAddressState();
}

class _StudioComfyAddressState extends State<StudioComfyAddress> {
  late final TextEditingController _text = TextEditingController(
    text: widget.url,
  );
  final FocusNode _focus = FocusNode();
  String? _error;
  String _status = '';
  bool _testing = false;
  String? _committed;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(StudioComfyAddress old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url && !_focus.hasFocus) _text.text = widget.url;
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final typed = _text.text.trim();
    // Submitting also leaves the field: one save and one test, not two.
    if (typed == _committed) return;
    _committed = typed;
    if (typed.isEmpty) {
      setState(() {
        _error = null;
        _status = 'Looking for ComfyUI on this computer.';
      });
      await widget.onSave('');
      return;
    }
    final address = normalizeComfyAddress(typed);
    if (address == null) {
      setState(() => _error = 'Use a host and port, like 127.0.0.1:8188.');
      return;
    }
    setState(() => _error = null);
    if (address != widget.url || !widget.explicit) {
      await widget.onSave(address);
    }
    if (mounted) _text.text = address;
    await _test(address);
  }

  Future<void> _test(String address) async {
    setState(() {
      _testing = true;
      _status = 'Testing…';
    });
    final up = await widget.answers(address);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _status = up
          ? 'ComfyUI answers at $address.'
          : 'Nothing answers at $address. Saved anyway.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondary(context);
    final offer = widget.offer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _focus,
                decoration: InputDecoration(
                  labelText: 'ComfyUI address',
                  hintText: '127.0.0.1:8188',
                  helperText: widget.explicit
                      ? null
                      : 'Found automatically. Type one to keep it.',
                  errorText: _error,
                  isDense: true,
                ),
                onSubmitted: (_) => _commit(),
              ),
            ),
            TextButton(
              onPressed: _testing
                  ? null
                  : () {
                      final address = normalizeComfyAddress(_text.text);
                      if (address == null) {
                        setState(
                          () => _error =
                              'Use a host and port, like 127.0.0.1:8188.',
                        );
                        return;
                      }
                      _test(address);
                    },
              child: const Text('Test'),
            ),
          ],
        ),
        if (_status.isNotEmpty)
          Text(_status, style: TextStyle(color: secondary, fontSize: 12)),
        if (offer != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  'ComfyUI answers at $offer',
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: () {
                  _text.text = offer;
                  widget.onSave(offer);
                },
                child: const Text('Use this'),
              ),
            ],
          ),
      ],
    );
  }
}
