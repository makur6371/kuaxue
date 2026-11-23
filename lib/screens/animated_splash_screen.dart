import 'dart:math';
import 'package:flutter/material.dart';

class AnimatedSplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const AnimatedSplashScreen({super.key, required this.onComplete});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _plateScale;
  late final Animation<double> _plateFade;
  late final Animation<double> _glowFade;
  late final Animation<double> _shinePos;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Plate slides in: 0 - 820ms
    _plateFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.41, curve: Curves.easeOut)),
    );
    _plateScale = Tween(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.41, curve: Curves.easeOutCubic)),
    );

    // Logo reveals: 240ms - 1420ms
    _fade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.12, 0.65, curve: Curves.easeOut)),
    );
    _scale = Tween(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.12, 0.65, curve: Curves.easeOutCubic)),
    );

    // Glow pulse: 540ms - 2240ms
    _glowFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.27, 1.0, curve: Curves.easeOut)),
    );

    // Shine sweep: 980ms - 1960ms
    _shinePos = Tween(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.49, 0.98, curve: Curves.easeInOut)),
    );

    _ctrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 200), widget.onComplete);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final logoSize = min(size.width, size.height) * 0.55;

    return Scaffold(
      backgroundColor: const Color(0xFFF5FBF8),
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return SizedBox(
              width: logoSize,
              height: logoSize,
              child: Stack(
                children: [
                  // Green gradient plate
                  FadeTransition(
                    opacity: _plateFade,
                    child: ScaleTransition(
                      scale: _plateScale,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(logoSize * 0.24),
                          gradient: const LinearGradient(
                            begin: Alignment(-0.6, -0.8),
                            end: Alignment(0.6, 1),
                            colors: [
                              Color(0xFFA9EBCA),
                              Color(0xFF62D8AD),
                              Color(0xFF22B889),
                              Color(0xFF0CA582),
                            ],
                            stops: [0.0, 0.35, 0.74, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF065C48).withOpacity(0.18),
                              blurRadius: 70,
                              offset: const Offset(0, 28),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Glow pulse
                  FadeTransition(
                    opacity: _glowFade,
                    child: Container(
                      margin: EdgeInsets.all(logoSize * 0.07),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(logoSize * 0.24),
                        gradient: RadialGradient(
                          center: const Alignment(-0.04, -0.26),
                          radius: 0.38,
                          colors: [
                            Colors.white.withOpacity(0.2),
                            Colors.white.withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Logo image with reveal
                  FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: Container(
                        margin: EdgeInsets.all(logoSize * 0.07),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(logoSize * 0.2),
                          image: const DecorationImage(
                            image: AssetImage('assets/logonew.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Shine sweep
                  AnimatedBuilder(
                    animation: _shinePos,
                    builder: (context, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(logoSize * 0.24),
                        child: Transform.translate(
                          offset: Offset(_shinePos.value * logoSize, 0),
                          child: Transform.rotate(
                            angle: -18 * pi / 180,
                            child: Container(
                              width: logoSize * 0.15,
                              height: logoSize * 2,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.white.withOpacity(0),
                                    Colors.white.withOpacity(0.5),
                                    Colors.white.withOpacity(0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
