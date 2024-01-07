import 'dart:typed_data';

import 'browser.dart';
import 'shaders.dart';
import 'tessellation.dart';
import 'types.dart';
import 'wrapper.dart';
import 'package:vector_math/vector_math.dart';

Matrix4 _makeOrthograpgic(Size size) {
  var scale = Matrix4.identity()
    ..scale(2.0 / size.width, -2.0 / size.height, 0);
  var translate = Matrix4.identity()..translate(-1, 1.0, 0.5);
  return translate * scale;
}

Offset _tranformPoint(Offset v, Matrix4 m) {
  var w = v.dx * m[3] + v.dy * m[7] + m[15];
  var result = Offset(
      v.dx * m[0] + v.dy * m[4] + m[12], v.dx * m[1] + v.dy * m[5] + m[13]);

  // This is Skia's behavior, but it may be reasonable to allow UB for the w=0
  // case.
  if (w != 0) {
    w = 1 / w;
  }
  return result.scale(w);
}

Rect _computeTransformedBounds(Matrix4 transform, Rect source) {
  var a = _tranformPoint(source.topLeft, transform);
  var b = _tranformPoint(source.topRight, transform);
  var c = _tranformPoint(source.bottomLeft, transform);
  var d = _tranformPoint(source.bottomRight, transform);
  double minX = a.dx;
  double minY = a.dy;
  double maxX = a.dx;
  double maxY = a.dy;

  for (var pt in [b, c, d]) {
    if (pt.dx < minX) {
      minX = pt.dx;
    } else if (pt.dx > maxX) {
      maxX = pt.dx;
    }

    if (pt.dy < minY) {
      minY = pt.dy;
    } else if (pt.dy > maxY) {
      maxY = pt.dy;
    }
  }

  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// The canvas class is the interface for recording drawing operations.
/// As these operations are recorded, an intermediate data structure is built up.
/// This data structure is later used to produce the render passes necessary to render
/// the recorded operations.
class Canvas {
  Canvas(this._context);

  final ContentContext _context;
  final List<Matrix4> _transformStack = <Matrix4>[
    Matrix4.identity(),
  ];

  DrawOp _currentNode = BaseLayer(Matrix4.identity());

  void drawRect(Rect rect, Paint paint) {
    var op = DrawRect(rect, paint, _transformStack.last.clone());
    op.parent = _currentNode;
    _currentNode.children.add(op);
  }

  void drawPath(Path path, Paint paint) {
    var op = DrawPath(path, paint, _transformStack.last.clone());
    op.parent = _currentNode;
    _currentNode.children.add(op);
  }

  void drawCircle(Circle circle, Paint paint) {
    var op = DrawCircle(circle, paint, _transformStack.last.clone());
    op.parent = _currentNode;
    _currentNode.children.add(op);
  }

  void drawPaint(Paint paint) {
    var op = DrawPaint(paint, _transformStack.last.clone());
    op.parent = _currentNode;
    _currentNode.children.add(op);
  }

  void save() {
    var transform = _transformStack.last.clone();
    _transformStack.add(transform);
  }

  void restore() {
    _currentNode = _currentNode.parent!;

    // Unclear what order this happens in.
    _transformStack.removeLast();
  }

  void saveLayer(Paint paint) {
    var op = SaveLayer(paint, _transformStack.last.clone());
    op.parent = _currentNode;
    _currentNode.children.add(op);
    _currentNode = op;

    // Unclear what order this happens in.
    var transform = _transformStack.last.clone();
    _transformStack.add(transform);
  }

  void _drawRect(DrawRect drawRect, RenderPass pass) {
    var rect = drawRect.rect;
    var paint = drawRect.paint;
    var hostData = Float32List(12);
    var offset = 0;
    hostData[offset++] = rect.left;
    hostData[offset++] = rect.top;
    hostData[offset++] = rect.right;
    hostData[offset++] = rect.top;
    hostData[offset++] = rect.left;
    hostData[offset++] = rect.bottom;

    hostData[offset++] = rect.left;
    hostData[offset++] = rect.bottom;
    hostData[offset++] = rect.right;
    hostData[offset++] = rect.top;
    hostData[offset++] = rect.right;
    hostData[offset++] = rect.bottom;

    var deviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: hostData.lengthInBytes);
    deviceBuffer.update(hostData);
    var view = deviceBuffer.asView();

    var uniformData = Float32List(24);
    offset = 0;
    var currentTransform = _makeOrthograpgic(pass.size) * drawRect.transform;
    for (var i = 0; i < 16; i++) {
      uniformData[offset++] = currentTransform.storage[i];
    }

    uniformData[offset++] = paint.color.$1 * paint.color.$4;
    uniformData[offset++] = paint.color.$2 * paint.color.$4;
    uniformData[offset++] = paint.color.$3 * paint.color.$4;
    uniformData[offset++] = paint.color.$4;

    var uniformDeviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: uniformData.lengthInBytes);
    uniformDeviceBuffer.update(uniformData);
    var uniformView = uniformDeviceBuffer.asView();

    var pipeline = _context.getSolidColorPipeline(blendMode: paint.mode);
    var bindGroup = _context.context.createBindGroup(
        layout: pipeline.$2,
        entries: [(binding: 0, resource: BufferBindGroup(uniformView))]);

    pass.setPipeline(pipeline.$1);
    pass.setVertexBuffer(0, view);
    pass.setBindGroup(0, bindGroup);
    pass.draw(6);
  }

  void _drawCircle(DrawCircle drawCircle, RenderPass pass) {
    var circle = drawCircle.circle;
    var paint = drawCircle.paint;

    var currentTransform = drawCircle.transform;
    var tessellateResults = Tessellator.tessellateCircle(
        circle, currentTransform.getMaxScaleOnAxis());
    var vertexCount = tessellateResults.length ~/ 2;

    var deviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: tessellateResults.lengthInBytes);
    deviceBuffer.update(tessellateResults);
    var view = deviceBuffer.asView();

    var uniformData = Float32List(24);
    var offset = 0;
    var appliedTransform = _makeOrthograpgic(pass.size) * currentTransform;
    for (var i = 0; i < 16; i++) {
      uniformData[offset++] = appliedTransform.storage[i];
    }

    uniformData[offset++] = paint.color.$1 * paint.color.$4;
    uniformData[offset++] = paint.color.$2 * paint.color.$4;
    uniformData[offset++] = paint.color.$3 * paint.color.$4;
    uniformData[offset++] = paint.color.$4;

    var uniformDeviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: uniformData.lengthInBytes);
    uniformDeviceBuffer.update(uniformData);
    var uniformView = uniformDeviceBuffer.asView();

    var pipeline = _context.getSolidColorPipeline(blendMode: paint.mode);
    var bindGroup = _context.context.createBindGroup(
        layout: pipeline.$2,
        entries: [(binding: 0, resource: BufferBindGroup(uniformView))]);

    pass.setVertexBuffer(0, view);
    pass.setPipeline(pipeline.$1);
    pass.setBindGroup(0, bindGroup);
    pass.draw(vertexCount);
  }

  void _drawPath(DrawPath drawPath, RenderPass pass) {
    var path = drawPath.path;
    var paint = drawPath.paint;

    var currentTransform = drawPath.transform;
    var tessellateResults = Tessellator.tesselateFilledPath(
        path, currentTransform.getMaxScaleOnAxis());
    var vertexCount = tessellateResults.length ~/ 2;

    var deviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: tessellateResults.lengthInBytes);
    deviceBuffer.update(tessellateResults);
    var view = deviceBuffer.asView();

    var uniformData = Float32List(24);
    var offset = 0;
    var appliedTransform = _makeOrthograpgic(pass.size) * currentTransform;
    for (var i = 0; i < 16; i++) {
      uniformData[offset++] = appliedTransform.storage[i];
    }

    uniformData[offset++] = paint.color.$1 * paint.color.$4;
    uniformData[offset++] = paint.color.$2 * paint.color.$4;
    uniformData[offset++] = paint.color.$3 * paint.color.$4;
    uniformData[offset++] = paint.color.$4;

    var uniformDeviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: uniformData.lengthInBytes);
    uniformDeviceBuffer.update(uniformData);
    var uniformView = uniformDeviceBuffer.asView();

    var pipeline = _context.getSolidColorPipeline(blendMode: paint.mode);
    var bindGroup = _context.context.createBindGroup(
        layout: pipeline.$2,
        entries: [(binding: 0, resource: BufferBindGroup(uniformView))]);

    pass.setVertexBuffer(0, view);
    pass.setPipeline(pipeline.$1);
    pass.setBindGroup(0, bindGroup);
    pass.draw(vertexCount);
  }

  // only valid if srcRect == dstRect
  void _drawTexture(Rect rect, Paint paint, GPUTextureView textureView,
      RenderPass pass, Matrix4 transform) {
    var hostData = Float32List(24);
    var offset = 0;
    hostData[offset++] = rect.left;
    hostData[offset++] = rect.top;
    hostData[offset++] = 0;
    hostData[offset++] = 0;

    hostData[offset++] = rect.right;
    hostData[offset++] = rect.top;
    hostData[offset++] = 1;
    hostData[offset++] = 0;

    hostData[offset++] = rect.left;
    hostData[offset++] = rect.bottom;
    hostData[offset++] = 0;
    hostData[offset++] = 1;

    hostData[offset++] = rect.left;
    hostData[offset++] = rect.bottom;
    hostData[offset++] = 0;
    hostData[offset++] = 1;

    hostData[offset++] = rect.right;
    hostData[offset++] = rect.top;
    hostData[offset++] = 1;
    hostData[offset++] = 0;

    hostData[offset++] = rect.right;
    hostData[offset++] = rect.bottom;
    hostData[offset++] = 1;
    hostData[offset++] = 1;

    var deviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: hostData.lengthInBytes);
    deviceBuffer.update(hostData);
    var view = deviceBuffer.asView();

    var uniformData = Float32List(24);
    offset = 0;
    var currentTransform = _makeOrthograpgic(pass.size) * transform;
    for (var i = 0; i < 16; i++) {
      uniformData[offset++] = currentTransform.storage[i];
    }
    uniformData[offset++] = paint.color.$4;

    var uniformDeviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: uniformData.lengthInBytes);
    uniformDeviceBuffer.update(uniformData);
    var uniformView = uniformDeviceBuffer.asView();

    var pipeline = _context.getTextureFillPipeline(blendMode: paint.mode);
    var bindGroup = _context.context.createBindGroup(
      layout: pipeline.$2,
      entries: [
        (binding: 0, resource: BufferBindGroup(uniformView)),
        (binding: 1, resource: TextureBindGroup(textureView)),
        (
          binding: 2,
          resource: SamplerBindGroup(
            _context.context.createSampler(
              addressModeWidth: AddressMode.clampToEdge,
              addressModeHeight: AddressMode.clampToEdge,
              magFitler: MagFitler.nearest,
            ),
          )
        ),
      ],
    );

    pass.setPipeline(pipeline.$1);
    pass.setVertexBuffer(0, view);
    pass.setBindGroup(0, bindGroup);
    pass.draw(6);
  }

  void translate(double dx, double dy) {
    _transformStack.last.translate(dx, dy);
  }

  void scale(double dx, double dy) {
    _transformStack.last.scale(dx, dy);
  }

  void dispatch(RenderTarget target) {
    DrawOp rootNode = _currentNode;
    while (rootNode.parent != null) {
      rootNode = rootNode.parent!;
    }

    // First, the root node is always sized to the provided render target, i.e. the screen,
    // so we don't need to compute bounds first. All offscreen or child composition must have
    // bounds computed beforehand however.
    var baseNode = (rootNode as BaseLayer);
    baseNode.bounds =
        Rect.fromLTRB(0, 0, target.width.toDouble(), target.height.toDouble());

    var commandBuffer =
        _context.context.createCommandBuffer(label: 'Save Layer');
    var renderPass = commandBuffer.createRenderPass(
      label: 'Onscreen Render Pass',
      size: Size(target.width, target.height),
      attachments: [
        AttachmentDescriptor(
          clearColor: (0.0, 0.0, 0.0, 0.0),
          loadOp: LoadOP.clear,
          storeOp: StoreOp.discard,
          renderTarget: target,
        )
      ],
    );

    var result = _renderSubpass(target, renderPass, baseNode, baseNode.bounds!);

    renderPass.end();
    commandBuffer.submit();

    for (var texture in result.textures) {
      texture.destroy();
    }
  }

  SubmitResult _renderSubpass(
      RenderTarget target, RenderPass pass, DrawOp node, Rect bounds) {
    var result = SubmitResult();
    for (var child in node.children) {
      switch (child) {
        case DrawRect():
          {
            _drawRect(child, pass);
          }
        case DrawPath():
          {
            _drawPath(child, pass);
          }
        case DrawCircle():
          {
            _drawCircle(child, pass);
          }
        case DrawPaint(paint: var paint, transform: var transform):
          {
            _drawRect(DrawRect(bounds, paint, transform), pass);
          }
        case SaveLayer(paint: var paint, transform: var transform):
          {
            // This child requires compositing, recurse and produce a texture view.
            var childBounds = child.computeBounds() ?? bounds;
            var offscreenTarget = _context.createOffscreenTarget(
                width: childBounds.width().ceil(),
                height: childBounds.height().ceil());
            var commandBuffer =
                _context.context.createCommandBuffer(label: 'Save Layer');
            var renderPass = commandBuffer.createRenderPass(
              label: 'Offscreen Render Pass',
              size: childBounds.size(),
              attachments: [
                AttachmentDescriptor(
                  clearColor: (0.0, 0.0, 0.0, 0.0),
                  loadOp: LoadOP.clear,
                  storeOp: StoreOp.discard,
                  renderTarget: offscreenTarget,
                )
              ],
            );
            _renderSubpass(offscreenTarget, renderPass, child, childBounds);
            renderPass.end();
            commandBuffer.submit();

            _drawTexture(childBounds, paint,
                offscreenTarget.resolve!.createView(), pass, transform);

            result.buffers.add(commandBuffer);
            result.textures.add(offscreenTarget.texture);
            result.textures.add(offscreenTarget.resolve!);
          }
      }
    }
    return result;
  }

  void dispose() {}
}

class SubmitResult {
  final List<CommandBuffer> buffers = <CommandBuffer>[];
  final List<GPUTexture> textures = <GPUTexture>[];
}

class Paint {
  RGBAColor color = (0, 0, 0, 0);
  BlendMode mode = BlendMode.srcOver;
}

/// The following classes represent deferred drawing commands that are recorded by the canvas
/// and then played back in order to render. Defering the execution of the rendering code is necessary as
/// we don't necessarily know the correct sizes/bounds for the save layer textures until we've recorded all
/// operations. Defering drawing also gives us an opportunity to apply optimizations
/// (though this code doesn't do that yet), such as converting drawRect/drawPaint into the render pass
/// clear color, or dropping drawing commands that won't have any impact on the final rendering (due to opacity).

abstract base class DrawOp {
  DrawOp(this.transform);

  final Matrix4 transform;

  DrawOp? parent;

  List<DrawOp> get children => const [];

  Rect? computeBounds();
}

final class BaseLayer extends DrawOp {
  BaseLayer(super.transform);

  @override
  final List<DrawOp> children = <DrawOp>[];

  Rect? bounds;

  @override
  Rect? computeBounds() {
    /// Transform will always be identity.
    return bounds;
  }
}

final class DrawRect extends DrawOp {
  DrawRect(this.rect, this.paint, super.transform);

  final Rect rect;
  final Paint paint;

  @override
  Rect? computeBounds() {
    return _computeTransformedBounds(transform, rect);
  }
}

final class DrawPath extends DrawOp {
  DrawPath(this.path, this.paint, super.transform);

  final Path path;
  final Paint paint;

  @override
  Rect? computeBounds() {
    return _computeTransformedBounds(transform, path.bounds);
  }
}

final class DrawCircle extends DrawOp {
  DrawCircle(this.circle, this.paint, super.transform);

  final Circle circle;
  final Paint paint;

  @override
  Rect? computeBounds() {
    return _computeTransformedBounds(transform, circle.computeBounds());
  }
}

final class DrawPaint extends DrawOp {
  DrawPaint(this.paint, super.transform);

  final Paint paint;

  /// Draw paint is unbounded and increases the current
  /// save layer size to the maximum.
  @override
  Rect? computeBounds() {
    return null;
  }
}

final class SaveLayer extends DrawOp {
  SaveLayer(this.paint, super.transform);

  final Paint paint;
  Rect? _cachedBounds;
  bool _didCache = false;

  @override
  List<DrawOp> children = <DrawOp>[];

  /// Save bounds is the union of all child op bounds.
  @override
  Rect? computeBounds() {
    if (!_didCache) {
      if (children.isEmpty) {
        _cachedBounds = Rect.empty;
      } else {
        Rect? bounds = Rect.empty;
        for (var i = 0; i < children.length; i++) {
          var childBounds = children[i].computeBounds();
          if (childBounds == null) {
            bounds = null;
            break;
          }
          bounds = bounds!.union(childBounds);
        }
        // TODO: do I need to transform these bounds? I don't think so.
        _cachedBounds = bounds;
      }
      _didCache = true;
    }

    return _cachedBounds;
  }
}
