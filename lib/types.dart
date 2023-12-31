import 'dart:math' as math;

/// A sorted rectangle.
final class Rect {
  const Rect.fromLTRB(this.left, this.top, this.right, this.bottom)
      : assert(left <= right && top <= bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  static const empty = Rect.fromLTRB(0, 0, 0, 0);

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  bool operator ==(Object other) {
    return other is Rect &&
        other.left == left &&
        other.top == top &&
        other.right == right &&
        other.bottom == bottom;
  }

  /// Compute the union of this rect with [other], returning a new rect that encloses both rectangles.
  Rect union(Rect other) {
    return Rect.fromLTRB(
      math.min(left, other.left),
      math.min(top, other.top),
      math.max(right, other.right),
      math.max(bottom, other.bottom),
    );
  }

  Rect computeBounds() {
    return this;
  }

  double width() {
    return right - left;
  }

  double height() {
    return bottom - top;
  }

  /// Return the rounded up integral size of this rectangle.
  Size size() {
    return Size(width().ceil(), height().ceil());
  }
}

final class Size {
  const Size(this.width, this.height);

  final int width;
  final int height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  bool operator ==(Object other) {
    return other is Size && other.width == width && other.height == height;
  }
}

final class Offset {
  const Offset(this.dx, this.dy);

  final double dx;
  final double dy;

  static const zero = Offset(0, 0);

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  bool operator ==(Object other) {
    return other is Offset && other.dx == dx && other.dy == dy;
  }

  Offset operator +(Offset other) {
    return Offset(dx + other.dx, dy + other.dy);
  }

  Offset operator -(Offset other) {
    return Offset(dx - other.dx, dy - other.dy);
  }
}

final class Circle {
  const Circle(this.center, this.radius) : assert(radius >= 0);

  final Offset center;
  final double radius;

  @override
  int get hashCode => Object.hash(center, radius);

  @override
  bool operator ==(Object other) {
    return other is Circle && other.center == center && other.radius == radius;
  }

  Rect computeBounds() {
    return Rect.fromLTRB(center.dx - radius, center.dy - radius,
        center.dx + radius, center.dy + radius);
  }
}
