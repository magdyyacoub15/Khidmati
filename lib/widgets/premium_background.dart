import 'package:flutter/material.dart';
import 'dart:math';

class PremiumBackground extends StatefulWidget {
  final Widget child;

  const PremiumBackground({super.key, required this.child});

  @override
  State<PremiumBackground> createState() => _PremiumBackgroundState();
}

class _PremiumBackgroundState extends State<PremiumBackground>
    with SingleTickerProviderStateMixin {
  AnimationController? _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  Widget _buildAnimatedBlob({
    double? top,
    double? left,
    required Offset offset,
    required Color color,
    required double size,
  }) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.translate(
        offset: offset,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        if (_animationController != null)
          AnimatedBuilder(
            animation: _animationController!,
            builder: (context, child) {
              return Stack(
                children: [
                  _buildAnimatedBlob(
                    top: -50,
                    left: -50,
                    offset: Offset(
                      sin(_animationController!.value * 2 * pi) * 60,
                      cos(_animationController!.value * 2 * pi) * 40,
                    ),
                    color: Colors.white.withValues(alpha: 0.1),
                    size: 300,
                  ),
                  _buildAnimatedBlob(
                    top: 300,
                    left: 150,
                    offset: Offset(
                      cos(_animationController!.value * 2 * pi) * 70,
                      sin(_animationController!.value * 2 * pi) * 50,
                    ),
                    color: Colors.white.withValues(alpha: 0.07),
                    size: 250,
                  ),
                  _buildAnimatedBlob(
                    top: 600,
                    left: -30,
                    offset: Offset(
                      sin(_animationController!.value * 2 * pi) * 40,
                      -cos(_animationController!.value * 2 * pi) * 60,
                    ),
                    color: Colors.white.withValues(alpha: 0.05),
                    size: 200,
                  ),
                ],
              );
            },
          ),
        widget.child,
      ],
    );
  }
}
