import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_web_gpu/types.dart';

/// The tesselator turns provided geometry into triangles for easier rendering. Tessellation is one
/// of potentially many rendering techniques.
class Tessellator {
  static Float32List tessellateCircle(Circle circle, double scale) {
    var divisions = _computeDivisions(scale * circle.radius);

    var radianStep = (2 * math.pi) / divisions;
    var totalPoints = 3 + (divisions - 3) * 3;
    var results = Float32List(totalPoints * 2);

    /// Precompute all relative points and angles for a fixed geometry size.
    var elapsedAngle = 0.0;
    var angleTable = List.filled(divisions, Offset.zero);
    for (var i = 0; i < divisions; i++) {
      angleTable[i] = Offset(math.cos(elapsedAngle) * circle.radius,
          math.sin(elapsedAngle) * circle.radius);
      elapsedAngle += radianStep;
    }

    var center = circle.center;

    var origin = center + angleTable[0];

    var l = 0;
    results[l++] = origin.dx;
    results[l++] = origin.dy;

    var pt1 = center + angleTable[1];

    results[l++] = pt1.dx;
    results[l++] = pt1.dy;

    var pt2 = center + angleTable[2];
    results[l++] = pt2.dx;
    results[l++] = pt2.dy;

    for (var j = 0; j < divisions - 3; j++) {
      results[l++] = origin.dx;
      results[l++] = origin.dy;
      results[l++] = pt2.dx;
      results[l++] = pt2.dy;

      pt2 = center + angleTable[j + 3];
      results[l++] = pt2.dx;
      results[l++] = pt2.dy;
    }
    return results;
  }

  static int _computeDivisions(double scaledRadius) {
    if (scaledRadius < 1.0) {
      return 4;
    }
    if (scaledRadius < 2.0) {
      return 8;
    }
    if (scaledRadius < 12.0) {
      return 24;
    }
    if (scaledRadius < 22.0) {
      return 34;
    }
    return math.min(scaledRadius, 140.0).round();
  }
}
