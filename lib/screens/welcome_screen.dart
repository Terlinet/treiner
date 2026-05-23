import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:video_player/video_player.dart';
import 'category_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  // Panobianco Colors - Moved to public class for Painters to access
  static const Color panoOrange = Color(0xFFFF6B00); // Laranja vibrante Panobianco
  static const Color panoBlack = Color(0xFF0D0D0D); // Preto profundo
  static const Color panoDarkGray = Color(0xFF1A1A1A); // Cinza para contraste

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _glitchController;
  late AnimationController _marketingController;
  late VideoPlayerController _videoController;
  Offset _mousePos = Offset.zero;
  bool _videoInitialized = false;

  @override
  void initState() {
    super.initState();
    _mainController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    _glitchController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);

    _marketingController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();

    _initializeVideo();
  }

  void _initializeVideo() {
    // Note: Updated to use the correct file name provided by the user
    _videoController = VideoPlayerController.asset('assets/videos/TerlineT_Treiner.mp4')
      ..initialize().then((_) {
        setState(() {
          _videoInitialized = true;
        });
        _videoController.setLooping(true);
        _videoController.setVolume(0); // Muted by default for auto-play
        _videoController.play();
      }).catchError((error) {
        print("Video Error: $error");
      });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _glitchController.dispose();
    _marketingController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WelcomeScreen.panoBlack,
      body: MouseRegion(
        onHover: (event) {
          setState(() {
            _mousePos = Offset(
              (event.localPosition.dx / MediaQuery.of(context).size.width) - 0.5,
              (event.localPosition.dy / MediaQuery.of(context).size.height) - 0.5,
            );
          });
        },
        child: Stack(
          children: [
            // Layer 0: Full Background Video
            _buildBackgroundVideo(),

            // Layer 1: Panobianco Grid Vortex (Lower opacity to blend with video)
            _buildDeepSpace(),

            // Layer 2: Floating Equipment
            _buildFloatingObject(Icons.fitness_center, 0.2, 0.3, 80, WelcomeScreen.panoOrange, 1.5),
            _buildFloatingObject(Icons.bolt, 0.8, 0.2, 120, Colors.white70, 2.0),
            _buildFloatingObject(Icons.timer, 0.15, 0.75, 90, WelcomeScreen.panoOrange, 1.2),
            _buildFloatingObject(Icons.monitor_weight, 0.85, 0.8, 100, Colors.white60, 1.8),

            // Layer 3: Main UI Content (Title + Marketing)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHyperTitle(),
                  const SizedBox(height: 30),
                  _buildMarketingBanners(),
                ],
              ),
            ),

            // Layer 4: HUD Overlay
            _buildHUD(),

            // Bottom Action
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(child: _buildPanobiancoButton()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundVideo() {
    return Positioned.fill(
      child: Container(
        color: WelcomeScreen.panoBlack,
        child: Opacity(
          opacity: 0.4, // Adjusted for a cinematic feel
          child: _videoInitialized
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController.value.size.width,
                    height: _videoController.value.size.height,
                    child: VideoPlayer(_videoController),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildDeepSpace() {
    return AnimatedBuilder(
      animation: _mainController,
      builder: (context, child) {
        return Opacity(
          opacity: 0.5, // Reduced to blend with the video
          child: Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX(_mousePos.dy * 0.1)
              ..rotateY(_mousePos.dx * 0.1),
            alignment: Alignment.center,
            child: CustomPaint(
              painter: PanobiancoGridPainter(_mainController.value),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingObject(IconData icon, double x, double y, double size, Color color, double speedMult) {
    return AnimatedBuilder(
      animation: _mainController,
      builder: (context, child) {
        final double val = (_mainController.value * speedMult * 2 * math.pi);
        final double hoverX = _mousePos.dx * 40 * speedMult;
        final double hoverY = _mousePos.dy * 40 * speedMult;

        return Positioned(
          left: (MediaQuery.of(context).size.width * x) + hoverX,
          top: (MediaQuery.of(context).size.height * y) + hoverY + (math.sin(val) * 20),
          child: Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateX(val * 0.15)
              ..rotateY(val * 0.4),
            alignment: Alignment.center,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.2),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: size,
                color: color,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHyperTitle() {
    return AnimatedBuilder(
      animation: _glitchController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: List.generate(4, (index) {
            return Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..translate(
                  _mousePos.dx * (index * 15),
                  _mousePos.dy * (index * 15),
                  index * 8.0,
                ),
              child: Text(
                'TERLINET\nTREINER',
                textAlign: TextAlign.center,
                style: GoogleFonts.russoOne(
                  fontSize: 70,
                  height: 0.9,
                  color: [
                    WelcomeScreen.panoOrange.withOpacity(0.4),
                    Colors.white.withOpacity(0.3),
                    WelcomeScreen.panoOrange.withOpacity(0.6),
                    Colors.white,
                  ][index],
                  shadows: index == 3 ? [
                    const Shadow(color: WelcomeScreen.panoOrange, blurRadius: 25),
                  ] : null,
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildMarketingBanners() {
    final List<String> marketingTexts = [
      "TREINE COM INTELIGÊNCIA ARTIFICIAL",
      "VISÃO COMPUTACIONAL EM TEMPO REAL",
      "CORREÇÃO DE POSTURA INSTANTÂNEA",
      "PERSONAL TRAINER 5D EXCLUSIVO",
    ];

    return AnimatedBuilder(
      animation: _marketingController,
      builder: (context, child) {
        final int index = (_marketingController.value * marketingTexts.length).floor();
        return Opacity(
          opacity: math.sin(_marketingController.value * math.pi).clamp(0.0, 1.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: WelcomeScreen.panoOrange.withOpacity(0.1),
              border: Border.symmetric(
                horizontal: BorderSide(color: WelcomeScreen.panoOrange.withOpacity(0.5), width: 1),
              ),
            ),
            child: Text(
              marketingTexts[index % marketingTexts.length],
              textAlign: TextAlign.center,
              style: GoogleFonts.orbitron(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHUD() {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: HUDPainter(),
        ),
      ),
    );
  }

  // Removed _buildRightVideo as video is now full background

  Widget _buildPanobiancoButton() {
    return Container(
      height: 65,
      width: 320,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: WelcomeScreen.panoOrange.withOpacity(0.4),
            blurRadius: 25,
            spreadRadius: -2,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CategoryScreen()),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: WelcomeScreen.panoBlack,
          padding: EdgeInsets.zero,
          side: const BorderSide(color: WelcomeScreen.panoOrange, width: 2.5),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(5)), // Estilo mais robusto Panobianco
          ),
        ),
        child: Text(
          'ESCOLHER EXERCICIO',
          textAlign: TextAlign.center,
          style: GoogleFonts.orbitron(
            fontSize: 18,
            color: WelcomeScreen.panoOrange,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

class PanobiancoGridPainter extends CustomPainter {
  final double progress;
  PanobiancoGridPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = WelcomeScreen.panoOrange.withOpacity(0.08)
      ..strokeWidth = 1.2;

    final double centerX = size.width / 2;
    final double centerY = size.height / 2;

    // Vanishing lines
    for (var i = 0; i < 360; i += 20) {
      final double angle = i * math.pi / 180;
      canvas.drawLine(
        Offset(centerX, centerY),
        Offset(centerX + math.cos(angle) * 1200, centerY + math.sin(angle) * 1200),
        paint,
      );
    }

    // Expanding rectangles (instead of circles for a more industrial look)
    for (var i = 1; i < 8; i++) {
      final s = ((i * 120) + (progress * 120)) % 1000;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(centerX, centerY), width: s.toDouble(), height: s.toDouble()),
        paint..color = WelcomeScreen.panoOrange.withOpacity(0.05 * (1 - s/1000)),
      );
    }
  }

  @override
  bool shouldRepaint(PanobiancoGridPainter oldDelegate) => true;
}

class HUDPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = WelcomeScreen.panoOrange.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Corner L-shapes
    const s = 30.0;
    const margin = 20.0;

    // Top Left
    canvas.drawPath(Path()..moveTo(margin + s, margin)..lineTo(margin, margin)..lineTo(margin, margin + s), paint);
    // Top Right
    canvas.drawPath(Path()..moveTo(size.width - margin - s, margin)..lineTo(size.width - margin, margin)..lineTo(size.width - margin, margin + s), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
