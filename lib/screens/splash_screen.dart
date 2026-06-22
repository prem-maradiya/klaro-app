import 'package:flutter/material.dart';
import '../theme/klaro.dart';
import 'auth_gate.dart';

/// Animated brand splash: K mark scales 0.86→1 and fades in (500ms, Klaro
/// ease), then the wordmark fades up — auto-routes to Home at ~1.8s.
/// Honors reduced-motion (fade only, shorter hold).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _markScale;
  late final Animation<double> _markFade;
  late final Animation<double> _wordFade;
  late final Animation<Offset> _wordRise;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // 0–500ms mark, 650–950ms wordmark (matches the icon-handoff motion spec).
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _markScale = Tween(begin: 0.86, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.53, curve: Klaro.ease),
    ));
    _markFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.42, curve: Curves.easeOut),
    );
    _wordFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.68, 1.0, curve: Curves.easeOut),
    );
    _wordRise = Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.68, 1.0, curve: Curves.easeOut),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller.value = 1.0;
      await Future.delayed(const Duration(milliseconds: 700));
    } else {
      _controller.forward();
      await Future.delayed(const Duration(milliseconds: 1800));
    }
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AuthGate(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: Klaro.durBase,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Klaro.tile, // matches the native splash for a seamless hand-off
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _markFade,
              child: ScaleTransition(
                scale: _markScale,
                child: Image.asset(
                  'assets/brand/klaro_mark.png',
                  width: 132,
                  height: 132,
                ),
              ),
            ),
            const SizedBox(height: 20),
            FadeTransition(
              opacity: _wordFade,
              child: SlideTransition(
                position: _wordRise,
                child: ShaderMask(
                  shaderCallback: (bounds) =>
                      Klaro.gradient.createShader(bounds),
                  child: const Text(
                    'Klaro',
                    style: TextStyle(
                      fontFamily: Klaro.display,
                      fontSize: 36,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1,
                      color: Colors.white, // masked by the gradient
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
