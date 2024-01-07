import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_web_gpu/types.dart';

// The default tolerance value for QuadraticCurveComponent::AppendPolylinePoints
// and CubicCurveComponent::AppendPolylinePoints. It also impacts the number of
// quadratics created when flattening a cubic curve to a polyline.
//
// Smaller numbers mean more points. This number seems suitable for particularly
// curvy curves at scales close to 1.0. As the scale increases, this number
// should be divided by Matrix::GetMaxBasisLength to avoid generating too few
// points for the given scale.
const double kDefaultCurveTolerance = 0.1;

// Based on https://en.wikipedia.org/wiki/B%C3%A9zier_curve#Specific_cases

double _linearSolve(double t, double p0, double p1) {
  return p0 + t * (p1 - p0);
}

double _quadraticSolve(double t, double p0, double p1, double p2) {
  return (1 - t) * (1 - t) * p0 + //
      2 * (1 - t) * t * p1 + //
      t * t * p2;
}

double _quadraticSolveDerivative(double t, double p0, double p1, double p2) {
  return 2 * (1 - t) * (p1 - p0) + //
      2 * t * (p2 - p1);
}

double _cubicSolve(double t, double p0, double p1, double p2, double p3) {
  return (1 - t) * (1 - t) * (1 - t) * p0 + //
      3 * (1 - t) * (1 - t) * t * p1 + //
      3 * (1 - t) * t * t * p2 + //
      t * t * t * p3;
}

double _cubicSolveDerivative(
    double t, double p0, double p1, double p2, double p3) {
  return -3 * p0 * (1 - t) * (1 - t) + //
      p1 * (3 * (1 - t) * (1 - t) - 6 * (1 - t) * t) +
      p2 * (6 * (1 - t) * t - 3 * t * t) + //
      3 * p3 * t * t;
}

Offset _solveQuadradicPath(double time, Offset p1, Offset p2, Offset cp) {
  return Offset(
    _quadraticSolve(time, p1.dx, cp.dx, p2.dx), // x
    _quadraticSolve(time, p1.dy, cp.dy, p2.dy), // y
  );
}

Offset _solveDerivativeQuadradicPath(
    double time, Offset p1, Offset p2, Offset cp) {
  return Offset(
    _quadraticSolveDerivative(time, p1.dx, cp.dx, p2.dx), // x
    _quadraticSolveDerivative(time, p1.dy, cp.dy, p2.dy), // y
  );
}

double _approximateParabolaIntegral(double x) {
  const double d = 0.67;
  return x / (1.0 - d + math.sqrt(math.sqrt(math.pow(d, 4) + 0.25 * x * x)));
}

double hypot(double x, double y) {
  return math.sqrt(math.pow(x, 2) + math.pow(y, 2));
}

void _appendPolylinePointsQuadraidcPath(
    Offset p1, Offset p2, Offset cp, double scaleFactor, List<Offset> points) {
  var tolerance = kDefaultCurveTolerance / scaleFactor;
  var sqrtTolerance = math.sqrt(tolerance);

  var d01 = cp - p1;
  var d12 = p2 - cp;
  var dd = d01 - d12;
  var cross = (p2 - p1).cross(dd);
  var x0 = d01.dot(dd) * 1 / cross;
  var x2 = d12.dot(dd) * 1 / cross;
  var scale = (cross / (hypot(dd.dx, dd.dy) * (x2 - x0))).abs();

  var a0 = _approximateParabolaIntegral(x0);
  var a2 = _approximateParabolaIntegral(x2);
  double val = 0.0;
  if (scale != double.infinity && scale != double.negativeInfinity) {
    var da = (a2 - a0).abs();
    var sqrtScale = math.sqrt(scale);
    if ((x0 < 0 && x2 < 0) || (x0 >= 0 && x2 >= 0)) {
      val = da * sqrtScale;
    } else {
      // cusp case
      var xmin = sqrtTolerance / sqrtScale;
      val = sqrtTolerance * da / _approximateParabolaIntegral(xmin);
    }
  }
  var u0 = _approximateParabolaIntegral(a0);
  var u2 = _approximateParabolaIntegral(a2);
  var uscale = 1 / (u2 - u0);

  var lineCount = math.max(1.0, (0.5 * val / sqrtTolerance).ceil());
  var step = 1 / lineCount;
  for (int i = 1; i < lineCount; i += 1) {
    var u = i * step;
    var a = a0 + (a2 - a0) * u;
    var t = (_approximateParabolaIntegral(a) - u0) * uscale;
    points.add(_solveQuadradicPath(t, p1, p2, cp));
  }
  points.add(p2);
}

/// The tesselator turns provided geometry into triangles for easier rendering. Tessellation is one
/// of potentially many rendering techniques.
class Tessellator {
  /// Tessellate a path into a series of triangles.
  ///
  /// This output is designed for use with a stencil and cover algorithm and will
  /// not be correct if used as standard fill if the path was not convex.
  static Float32List tesselateFilledPath(Path path, double scale) {
    var polyline = <Offset>[];
    var countourRanges = <(int, int)>[];
    var currentContourStart = 0;
    for (var (verb, a, b, c) in path) {
      switch (verb) {
        case PathVerb.close:
          polyline.add(a);
          polyline.add(b);
          countourRanges.add((currentContourStart, polyline.length));
          currentContourStart = polyline.length;
          continue;
        case PathVerb.line:
          polyline.add(a);
          polyline.add(b);
          continue;
        case PathVerb.quadraticBezier:
          _appendPolylinePointsQuadraidcPath(a, b, c!, scale, polyline);
          continue;
      }
    }
    if (countourRanges.isEmpty) {
      countourRanges.add((0, polyline.length));
    }

    var output = <Offset>[];
    for (var j = 0; j < countourRanges.length; j++) {
      var (start, end) = countourRanges[j];
      var firstPoint = polyline[start];

      // Some polygons will not self close and an additional triangle
      // must be inserted, others will self close and we need to avoid
      // inserting an extra triangle.
      if (polyline[end - 1] == firstPoint) {
        end--;
      }

      if (j > 0) {
        // Triangle strip break.
        output.add(output.last);
        output.add(firstPoint);
        output.add(firstPoint);
      } else {
        output.add(firstPoint);
      }

      var a = start + 1;
      var b = end - 1;
      while (a < b) {
        output.add(polyline[a]);
        output.add(polyline[b]);
        a++;
        b--;
      }
      if (a == b) {
        output.add(polyline[a]);
      }
    }

    var data = Float32List(output.length * 2);
    for (var i = 0, j = 0; i < output.length; i++) {
      data[j++] = output[i].dx;
      data[j++] = output[i].dy;
    }
    return data;
  }

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
    return math.min(scaledRadius, 240.0).round();
  }
}
