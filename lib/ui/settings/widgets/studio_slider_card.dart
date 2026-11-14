// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/gen_presets/gen_presets.dart';

import 'studio_slider_track_shape.dart';

/// Compact studio parameter card for Generation settings:
/// Displays label, tooltip, reset button, tabular numeric input, and custom
/// slider with danger zone styling and a graphical default pip.
/// Decouples visual slider bounds from user-typed input, preventing clamping
/// or truncation of extreme, preset, or legacy values.
class StudioSliderCard extends StatefulWidget {
  const StudioSliderCard({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.defaultVal,
    this.dangerMin,
    this.dangerMax,
    this.divisions,
    this.isInteger = false,
    this.decimalPlaces = 2,
    this.reset,
    this.tooltip,
    this.embedded = false,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double? defaultVal;
  final double? dangerMin;
  final double? dangerMax;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final bool isInteger;
  final int decimalPlaces;
  final ResetTarget? reset;
  final String? tooltip;
  final bool embedded;

  @override
  State<StudioSliderCard> createState() => _StudioSliderCardState();
}

class _StudioSliderCardState extends State<StudioSliderCard> {
  late final FocusNode _focusNode;
  late final TextEditingController _controller;
  late String _formattedValue;
  double? _dragValue;

  String _format(double v) => widget.isInteger
      ? v.toInt().toString()
      : v.toStringAsFixed(widget.decimalPlaces);

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _formattedValue = _format(widget.value);
    _controller = TextEditingController(text: _formattedValue);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant StudioSliderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.decimalPlaces != widget.decimalPlaces ||
        oldWidget.isInteger != widget.isInteger) {
      _formattedValue = _format(widget.value);
      if (!_focusNode.hasFocus) {
        _controller.text = _formattedValue;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commitValue();
    }
  }

  void _commitValue() {
    final text = _controller.text.trim();
    if (text == _formattedValue) {
      return;
    }
    if (text.isEmpty) {
      _controller.text = _formattedValue;
      return;
    }
    final num? parsed = widget.isInteger
        ? int.tryParse(text)
        : double.tryParse(text);
    if (parsed == null || parsed < 0) {
      _controller.text = _formattedValue;
      return;
    }
    final double nextVal = parsed.toDouble();
    if ((nextVal - widget.value).abs() > 1e-7) {
      widget.onChanged(nextVal);
    }
    _formattedValue = _format(nextVal);
    _controller.text = _formattedValue;
  }

  Widget? _buildResetButton() {
    final target = widget.reset;
    if (target == null) return null;
    final differs = widget.isInteger
        ? widget.value.round() != target.value.round()
        : (widget.value - target.value).abs() > 1e-6;
    if (!differs) return null;
    return ValueResetButton(
      tooltip: 'Reset to ${_format(target.value)}, ${target.source}',
      onPressed: () => widget.onChanged(target.value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resetButton = _buildResetButton();
    final current = _dragValue ?? widget.value;
    final clampedSliderValue = current.clamp(widget.min, widget.max);

    final bool inUpperDanger =
        (widget.dangerMax != null && current > widget.dangerMax!) ||
        current > widget.max;
    final bool inLowerDanger =
        (widget.dangerMin != null && current < widget.dangerMin!) ||
        current < widget.min;
    final bool inDanger = inUpperDanger || inLowerDanger;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.tooltip != null)
                      Tooltip(
                        triggerMode: TooltipTriggerMode.tap,
                        message: widget.tooltip!,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.info_outline,
                            size: 14,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (resetButton != null) ...[
                resetButton,
                const SizedBox(width: 4),
              ],
              SizedBox(
                width: 72,
                height: 28,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: widget.isInteger
                      ? TextInputType.number
                      : const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: AppColors.textPrimary(context),
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: InkColors.fieldEdgeOf(context),
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: InkColors.fieldEdgeOf(context),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: AppColors.formAccentOf(context),
                        width: 1.5,
                      ),
                    ),
                    filled: true,
                    fillColor: AppColors.hairlineOf(context, 0.05),
                  ),
                  onSubmitted: (_) => _commitValue(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: StudioSliderTrackShape(
                min: widget.min,
                max: widget.max,
                defaultVal: widget.defaultVal,
                dangerMin: widget.dangerMin,
                dangerMax: widget.dangerMax,
                dangerActiveColor: AppColors.negativeAccentOf(context),
                dangerInactiveColor:
                    AppColors.negativeAccentOf(context).withValues(alpha: 0.35),
                pipColor:
                    AppColors.textSecondary(context).withValues(alpha: 0.75),
              ),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: inDanger
                  ? AppColors.negativeAccentOf(context)
                  : AppColors.formAccentOf(context),
              inactiveTrackColor: AppColors.hairlineOf(context, 0.15),
              thumbColor: inDanger
                  ? AppColors.negativeAccentOf(context)
                  : AppColors.formAccentOf(context),
            ),
            child: Slider(
              value: clampedSliderValue,
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              onChanged: (v) {
                setState(() => _dragValue = v);
                _controller.text = _format(v);
              },
              onChangeEnd: (v) {
                widget.onChanged(v);
                _formattedValue = _format(v);
                _controller.text = _formattedValue;
                setState(() => _dragValue = null);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_endLabel(widget.min), style: _endStyle(context)),
                Text(_endLabel(widget.max), style: _endStyle(context)),
              ],
            ),
          ),
        ],
    );

    if (widget.embedded) {
      return body;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.hairlineOf(context, 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.hairlineOf(context, 0.12),
          width: 1,
        ),
      ),
      child: body,
    );
  }

  String _endLabel(double v) => _format(v);

  TextStyle _endStyle(BuildContext context) => TextStyle(
        fontSize: 11,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: AppColors.textTertiary(context),
      );
}
