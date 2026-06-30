import 'package:flutter/material.dart';

class CustomButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final List<Color>? gradient;
  final IconData? icon;

  const CustomButton({
    Key? key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.gradient,
    this.icon,
  }) : super(key: key);

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultGradient = widget.gradient ?? [
      theme.colorScheme.primary,
      theme.colorScheme.secondary,
    ];

    return MouseRegion(
      cursor: widget.onPressed != null && !widget.isLoading
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: widget.onPressed != null && !widget.isLoading
            ? (_) => _controller.forward()
            : null,
        onTapUp: widget.onPressed != null && !widget.isLoading
            ? (_) {
                _controller.reverse();
                widget.onPressed!();
              }
            : null,
        onTapCancel: widget.onPressed != null && !widget.isLoading
            ? () => _controller.reverse()
            : null,
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) => Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          ),
          child: Container(
            height: 56.0,
            decoration: BoxDecoration(
              gradient: widget.onPressed != null
                  ? LinearGradient(
                      colors: defaultGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: widget.onPressed == null ? Colors.white.withOpacity(0.05) : null,
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: widget.onPressed != null
                  ? [
                      BoxShadow(
                        color: defaultGradient.first.withOpacity(0.3),
                        blurRadius: 16.0,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [],
              border: widget.onPressed == null
                  ? Border.all(color: Colors.white.withOpacity(0.05), width: 1.0)
                  : null,
            ),
            alignment: Alignment.center,
            child: widget.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2.5,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        widget.text,
                        style: TextStyle(
                          color: widget.onPressed != null
                              ? Colors.white
                              : Colors.white.withOpacity(0.3),
                          fontSize: 16.0,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
