import 'dart:typed_data';

import 'browser.dart';
import 'shaders.dart';
import 'tessellation.dart';
import 'types.dart';
import 'wrapper.dart';
import 'package:vector_math/vector_math.dart';

/// Translate this matrix by a [Vector3], [Vector4], or x,y,z
Matrix4 translate(Matrix4 mat, double x, [double y = 0.0, double z = 0.0]) {
  var storage = mat.storage;
  double tx;
  double ty;
  double tz;
  double tw = 1.0;
  tx = x;
  ty = y;
  tz = z;
  final t1 =
      storage[0] * tx + storage[4] * ty + storage[8] * tz + storage[12] * tw;
  final t2 =
      storage[1] * tx + storage[5] * ty + storage[9] * tz + storage[13] * tw;
  final t3 =
      storage[2] * tx + storage[6] * ty + storage[10] * tz + storage[14] * tw;
  final t4 =
      storage[3] * tx + storage[7] * ty + storage[11] * tz + storage[15] * tw;
  storage[12] = t1;
  storage[13] = t2;
  storage[14] = t3;
  storage[15] = t4;
  return mat;
}

Matrix4 _makeOrthograpgic(Size size) {
  var scale = Matrix4.identity()
    ..scale(2.0 / size.width, -2.0 / size.height, 0);
  return translate(Matrix4.identity(), -1, 1.0, 0.5) * scale;
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
  Canvas(this._context)
      : _uniformBuffer = _context.context.createDeviceBuffer(
            lengthInBytes: kDeviceBufferSizeFloats * 4,
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST),
        _vertexBuffer = _context.context.createDeviceBuffer(
            lengthInBytes: kDeviceBufferSizeFloats * 4,
            usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST);

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

  Matrix4 currentTransform_ = Matrix4.identity();

  static const kDeviceBufferSizeFloats = 1024 * 1024;

  final Float32List _stagingBufferUniforms =
      Float32List(kDeviceBufferSizeFloats);
  final Float32List _stagingBufferVertexData =
      Float32List(kDeviceBufferSizeFloats);

  DeviceBuffer _uniformBuffer;
  DeviceBuffer _vertexBuffer;
  int _uniformOffset = 0;
  int _vertexOffset = 0;

  GPUBindGroup? solidBind;
  Matrix4? _hackCacheTransform;
  GPURenderPipeline? lastPipeline;

  void _configuirePipeline(Paint paint, RenderPass pass, Matrix4 transform) {
    // Flush Prev Buffer.
    if (_uniformOffset + 64 > kDeviceBufferSizeFloats) {
      _uniformBuffer.update(_stagingBufferUniforms, offset: 0);
      _uniformBuffer = _context.context.createDeviceBuffer(
          lengthInBytes: kDeviceBufferSizeFloats * 4,
          usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST);
      _uniformOffset = 0;
      solidBind = null;
    }

    // Solid Color.
    var uniformView =
        _uniformBuffer.asView(offset: _uniformOffset * 4, size: 256);
    var startOffset = _uniformOffset * 4;
    Matrix4 currentTransform =
        (_hackCacheTransform ??= (_makeOrthograpgic(pass.size) * transform));
    // This is faster for some reason.
    {
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[0];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[1];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[2];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[3];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[4];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[5];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[6];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[7];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[8];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[9];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[10];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[11];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[12];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[13];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[14];
      _stagingBufferUniforms[_uniformOffset++] = currentTransform.storage[15];
    }

    _stagingBufferUniforms[_uniformOffset++] = paint.color.$1 * paint.color.$4;
    _stagingBufferUniforms[_uniformOffset++] = paint.color.$2 * paint.color.$4;
    _stagingBufferUniforms[_uniformOffset++] = paint.color.$3 * paint.color.$4;
    _stagingBufferUniforms[_uniformOffset++] = paint.color.$4;
    // Alignment
    _uniformOffset += 44;

    var pipeline = _context.getSolidColorPipeline(blendMode: paint.mode);

    if (!identical(lastPipeline, pipeline.$1)) {
      pass.setPipeline(pipeline.$1);
      lastPipeline = pipeline.$1;
    }
    solidBind ??= _context.context.createFastBindGroup(
        layout: pipeline.$2,
        binding: 0,
        resource: BufferBindGroup(uniformView));
    pass.setBindGroup(0, solidBind!, startOffset);
  }

  void _drawRect(DrawRect drawRect, RenderPass pass) {
    var rect = drawRect.rect;
    var paint = drawRect.paint;

    if (_vertexOffset + 64 > kDeviceBufferSizeFloats) {
      _vertexBuffer.update(_stagingBufferVertexData, offset: 0);
      _vertexBuffer = _context.context.createDeviceBuffer(
          lengthInBytes: kDeviceBufferSizeFloats * 4,
          usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST);
      _vertexOffset = 0;
    }

    var vertexView = _vertexBuffer.asView(offset: _vertexOffset * 4, size: 256);

    _stagingBufferVertexData[_vertexOffset++] = rect.left;
    _stagingBufferVertexData[_vertexOffset++] = rect.top;
    _stagingBufferVertexData[_vertexOffset++] = rect.right;
    _stagingBufferVertexData[_vertexOffset++] = rect.top;
    _stagingBufferVertexData[_vertexOffset++] = rect.left;
    _stagingBufferVertexData[_vertexOffset++] = rect.bottom;

    _stagingBufferVertexData[_vertexOffset++] = rect.left;
    _stagingBufferVertexData[_vertexOffset++] = rect.bottom;
    _stagingBufferVertexData[_vertexOffset++] = rect.right;
    _stagingBufferVertexData[_vertexOffset++] = rect.top;
    _stagingBufferVertexData[_vertexOffset++] = rect.right;
    _stagingBufferVertexData[_vertexOffset++] = rect.bottom;
    // Align to 256
    _vertexOffset += (64 - 12);

    _configuirePipeline(paint, pass, drawRect.transform);
    pass.setVertexBuffer(0, vertexView);
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

    _configuirePipeline(paint, pass, drawCircle.transform);
    pass.setVertexBuffer(0, view);
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

    _configuirePipeline(paint, pass, drawPath.transform);
    pass.setVertexBuffer(0, view);
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
    renderPass.setScissorRect(0, 0, target.width, target.height);
    var result = _renderSubpass(target, renderPass, baseNode, baseNode.bounds!);

    if (_vertexOffset != 0) {
      _vertexBuffer.update(_stagingBufferVertexData,
          offset: 0, size: _vertexOffset * 4);
      _vertexOffset = 0;
    }
    if (_uniformOffset != 0) {
      _uniformBuffer.update(_stagingBufferUniforms,
          offset: 0, size: _uniformOffset * 4);
      _uniformOffset = 0;
    }
    solidBind = null;
    lastPipeline = null;

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

class LinearGradient {
  RGBAColor start = (0, 0, 0, 0);
  RGBAColor end = (0, 0, 0, 0);
  Offset from = Offset.zero;
  Offset to = Offset.zero;
}

class Paint {
  RGBAColor color = (0, 0, 0, 0);
  BlendMode mode = BlendMode.srcOver;
  LinearGradient? gradient;
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
