import 'package:flutter/material.dart';

class SliderWithInput extends StatefulWidget {
  const SliderWithInput({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.context,
    this.divisions,
    this.tooltip,
    this.isInteger = false,
    this.decimalPlaces = 2,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final Function(double) onChanged;
  final BuildContext context;
  final int? divisions;
  final String? tooltip;
  final bool isInteger;
  final int decimalPlaces;

  @override
  State<SliderWithInput> createState() => _SliderWithInputState();
}

class _SliderWithInputState extends State<SliderWithInput> {
  late final FocusNode _focusNode;
  late final TextEditingController _controller;
  late String _formattedValue;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _controller = TextEditingController(
      text: widget.isInteger
          ? widget.value.toInt().toString()
          : widget.value.toStringAsFixed(widget.decimalPlaces),
    );
    _formattedValue = widget.isInteger
        ? widget.value.toInt().toString()
        : widget.value.toStringAsFixed(widget.decimalPlaces);

    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant SliderWithInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.isInteger
          ? widget.value.toInt().toString()
          : widget.value.toStringAsFixed(widget.decimalPlaces);
      _formattedValue = widget.isInteger
          ? widget.value.toInt().toString()
          : widget.value.toStringAsFixed(widget.decimalPlaces);
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
    if (text.isEmpty) {
      _controller.text = _formattedValue;
      return;
    }
    final num? parsed = widget.isInteger
        ? int.tryParse(text)
        : double.tryParse(text);
    if (parsed == null) {
      _controller.text = _formattedValue;
      return;
    }
    final double clamped = parsed.toDouble().clamp(widget.min, widget.max);
    widget.onChanged(clamped);
    _formattedValue = widget.isInteger
        ? clamped.toInt().toString()
        : clamped.toStringAsFixed(widget.decimalPlaces);
    _controller.text = _formattedValue;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                if (widget.tooltip != null)
                  Tooltip(
                    message: widget.tooltip!,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.white38,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(
              width: 80,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: widget.isInteger
                    ? TextInputType.number
                    : const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.white24, width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.white24, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.blueAccent, width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                ),
                onSubmitted: (_) => _commitValue(),
              ),
            ),
          ],
        ),
        Slider(
          value: widget.value,
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}
