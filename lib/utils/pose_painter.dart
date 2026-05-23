import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../screens/welcome_screen.dart';

class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size absoluteImageSize;
  final InputImageRotation rotation;

  PosePainter(this.poses, this.absoluteImageSize, this.rotation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = WelcomeScreen.panoOrange;

    final jointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;

    for (final pose in poses) {
      // Desenhar conexões (ossos)
      pose.landmarks.forEach((_, landmark) {
        canvas.drawCircle(
          Offset(
            _translateX(landmark.x, rotation, size, absoluteImageSize),
            _translateY(landmark.y, rotation, size, absoluteImageSize),
          ),
          4,
          jointPaint,
        );
      });

      // Lógica de desenho de linhas entre pontos específicos (ex: Braços)
      _paintLine(canvas, size, pose, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, paint);
      _paintLine(canvas, size, pose, PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist, paint);
      _paintLine(canvas, size, pose, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow, paint);
      _paintLine(canvas, size, pose, PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist, paint);

      // Tronco e Pernas
      _paintLine(canvas, size, pose, PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, paint);
      _paintLine(canvas, size, pose, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, paint);
      _paintLine(canvas, size, pose, PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, paint);
      _paintLine(canvas, size, pose, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, paint);
      // ... Repetir para o lado direito conforme necessário
    }
  }

  void _paintLine(Canvas canvas, Size size, Pose pose, PoseLandmarkType startType, PoseLandmarkType endType, Paint paint) {
    final start = pose.landmarks[startType];
    final end = pose.landmarks[endType];
    if (start != null && end != null) {
      canvas.drawLine(
        Offset(
          _translateX(start.x, rotation, size, absoluteImageSize),
          _translateY(start.y, rotation, size, absoluteImageSize),
        ),
        Offset(
          _translateX(end.x, rotation, size, absoluteImageSize),
          _translateY(end.y, rotation, size, absoluteImageSize),
        ),
        paint,
      );
    }
  }

  double _translateX(double x, InputImageRotation rotation, Size size, Size absoluteImageSize) {
    return x * size.width / absoluteImageSize.width;
  }

  double _translateY(double y, InputImageRotation rotation, Size size, Size absoluteImageSize) {
    return y * size.height / absoluteImageSize.height;
  }

  @override
  bool shouldRepaint(PosePainter oldDelegate) {
    return oldDelegate.absoluteImageSize != absoluteImageSize || oldDelegate.poses != poses;
  }
}
