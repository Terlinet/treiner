import 'dart:math' as math;

class PoseUtils {
  /// Calcula o ângulo entre três pontos (A, B, C) sendo B o vértice.
  static double calculateAngle(
    math.Point<double> a,
    math.Point<double> b,
    math.Point<double> c,
  ) {
    double angle = math.atan2(c.y - b.y, c.x - b.x) -
                   math.atan2(a.y - b.y, a.x - b.x);
    angle = angle.abs() * 180 / math.pi;
    if (angle > 180) {
      angle = 360 - angle;
    }
    return angle;
  }
}

enum ExerciseStage { UP, DOWN }

class RepCounter {
  int count = 0;
  ExerciseStage stage = ExerciseStage.DOWN;

  // Lógica para Rosca Direta
  void updateBicepCurl(double angle) {
    if (angle > 160) {
      stage = ExerciseStage.DOWN;
    }
    if (angle < 40 && stage == ExerciseStage.DOWN) {
      stage = ExerciseStage.UP;
      count++;
    }
  }

  // Lógica para Agachamento
  void updateSquat(double angle) {
    if (angle > 160) {
      stage = ExerciseStage.UP;
    }
    if (angle < 90 && stage == ExerciseStage.UP) {
      stage = ExerciseStage.DOWN;
      count++;
    }
  }
}
