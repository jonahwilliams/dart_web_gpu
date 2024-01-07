import 'dart:math' as math;
import 'dart:typed_data';

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

  /// The top left corner of the rectangle.
  Offset get topLeft {
    return Offset(left, top);
  }

  /// The top right corner of the rectangle.
  Offset get topRight {
    return Offset(right, top);
  }

  /// The bottom left corner of the rectangle.
  Offset get bottomLeft {
    return Offset(left, bottom);
  }

  /// The bottom right corner of the rectangle.
  Offset get bottomRight {
    return Offset(right, bottom);
  }

  /// Return the rounded up integral size of this rectangle.
  Size size() {
    return Size(width().ceil(), height().ceil());
  }
}

/// Represents an integral size.
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

/// Represents an offset from the origin (0, 0).
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

  /// Compute dot product with [other].
  double dot(Offset other) {
    return (dx * other.dx) + (dy * other.dy);
  }

  /// Compute cross product with [other].
  double cross(Offset other) {
    return (dx * other.dy) - (dy * other.dx);
  }

  /// Scale each component of this offset by the value [s].
  Offset scale(num s) {
    return Offset(dx * s, dy * s);
  }

  @override
  String toString() => 'Offset($dx, $dy)';
}

/// Represents a circle defined by a [center] point and [radius].
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

/// A class used to dynamically build up a [Path] object.
final class PathBuilder {
  List<Offset> _points = [];
  List<PathVerb> _verbs = [];
  Offset _current = Offset.zero;
  Offset? _curveStart;
  Rect? _bounds;

  void close() {
    if (_curveStart == null) {
      return;
    }
    _verbs.add(PathVerb.close);
    _points.add(_current);
    _points.add(_curveStart!);
  }

  void lineTo(Offset offset) {
    _curveStart ??= _current;

    _points.add(_current);
    _points.add(offset);
    _verbs.add(PathVerb.line);

    _current = offset;
  }

  void moveTo(Offset offset) {
    _current = offset;
  }

  void quadraticBezierTo(Offset offset, Offset controlPoint) {
    _curveStart ??= _current;

    _points.add(_current);
    _points.add(offset);
    _points.add(controlPoint);
    _verbs.add(PathVerb.quadraticBezier);

    _current = offset;
  }

  /// Create a new [Path] and reset the current path builder.
  Path takePath() {
    var path = Path._(_points, _verbs, Rect.fromLTRB(0, 0, 500, 500));
    _points = [];
    _verbs = [];
    _bounds = null;
    return path;
  }
}

/// An enumeration of internal path states.
enum PathVerb {
  // Two points, current and next.
  close(2),
  // Two points, current and next.
  line(2),
  // Three points, current, next, and control point 1.
  quadraticBezier(3);

  const PathVerb(this.count);

  final int count;
}

/// A Path represents one or more contours composed of straight line, quadradic, or cubic beziers.
///
/// Paths do not define equality as the computation would be too expensive.
final class Path extends Iterable {
  const Path._(this._points, this._verbs, this.bounds);

  final List<Offset> _points;
  final List<PathVerb> _verbs;
  final Rect bounds;

  @override
  Iterator<(PathVerb, Offset, Offset, Offset?)> get iterator =>
      _PathIterator._(this);
}

final class _PathIterator
    implements Iterator<(PathVerb, Offset, Offset, Offset?)> {
  _PathIterator._(this._path);

  final Path _path;
  int _offset = 0;
  int _pointOffset = 0;

  @override
  (PathVerb, Offset, Offset, Offset?) get current {
    var verb = _path._verbs[_offset];
    return (
      verb,
      _path._points[_pointOffset],
      _path._points[_pointOffset + 1],
      (verb.count > 2) ? _path._points[_pointOffset + 2] : null,
    );
  }

  @override
  bool moveNext() {
    if (_offset < _path._verbs.length - 1) {
      _pointOffset += _path._verbs[_offset].count;
      _offset++;
      return true;
    }
    return false;
  }
}
