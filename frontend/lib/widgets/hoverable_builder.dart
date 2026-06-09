import 'package:flutter/material.dart';

class HoverableBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHovered) builder;

  const HoverableBuilder({super.key, required this.builder});

  @override
  State<HoverableBuilder> createState() => _HoverableBuilderState();
}

class _HoverableBuilderState extends State<HoverableBuilder> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: widget.builder(context, _isHovered),
    );
  }
}
