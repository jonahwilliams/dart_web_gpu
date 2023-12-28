import 'dart:typed_data';

import 'browser.dart';
import 'wrapper.dart';
import 'package:vector_math/vector_math.dart';
import 'dart:math' as math;

typedef PipelineAndLayout = (GPURenderPipeline, GPUBindGroupLayout);

class ContentContext {
  ContentContext(this.context, TextureFormat format) {
    _init(format);
  }

  final Context context;

  late final PipelineAndLayout solidColorPipeline;

  void _init(TextureFormat format) {
    var bindGroupLayout = context.createBindGroupLayout(entries: [
      BindGroupLayoutEntry(
        visibility: GPUShaderStage.FRAGMENT | GPUShaderStage.VERTEX,
        binding: 0,
        buffer: (
          hasDynamicOffset: false,
          minBindingSize: 0,
          type: BufferLayoutType.uniform,
        ),
      )
    ]);
    var pipelineLayout =
        context.createPipelineLayout(layouts: [bindGroupLayout]);

    var pipeline = context.createRenderPipeline(
      pipelineLayout: pipelineLayout,
      module: context.createShaderModule(code: '''
struct UniformData {
  mvp: mat4x4<f32>,
  color: vec4f,
};

@group(0) @binding(0)
var<uniform> uniform_data: UniformData;

@vertex
fn vertexMain(@location(0) pos: vec2f) ->
  @builtin(position) vec4f {
  return uniform_data.mvp * vec4f(pos, 0, 1);
}

@fragment
fn fragmentMain() -> @location(0) vec4f {
  return uniform_data.color;
}
  '''),
      label: 'Rect Shader',
      vertexEntrypoint: 'vertexMain',
      fragmentEntrypoint: 'fragmentMain',
      format: format,
      layouts: [
        (
          arrayStride: 8,
          attributes: [
            (
              format: ShaderType.float32x2,
              offset: 0,
              shaderLocation: 0, // Position, see vertex shader
            )
          ],
        ),
      ],
    );
    solidColorPipeline = (pipeline, bindGroupLayout);
  }
}

extension on (double, double) {
  (double, double) operator +((double, double) other) {
    return (this.$1 + other.$1, this.$2 + other.$2);
  }
}

class Tessellator {
  static Float32List tessellateCircle(
      double x, double y, double radius, double scale) {
    var divisions = computeDivisions(scale * radius);

    var radianStep = (2 * math.pi) / divisions;
    var totalPoints = 3 + (divisions - 3) * 3;
    var results = Float32List(totalPoints * 2);

    /// Precompute all relative points and angles for a fixed geometry size.
    var elapsedAngle = 0.0;
    var angleTable = List.filled(divisions, (0.0, 0.0));
    for (var i = 0; i < divisions; i++) {
      angleTable[i] =
          (math.cos(elapsedAngle) * radius, math.sin(elapsedAngle) * radius);
      elapsedAngle += radianStep;
    }

    var center = (x, y);

    var origin = center + angleTable[0];

    var l = 0;
    results[l++] = origin.$1;
    results[l++] = origin.$2;

    var pt1 = center + angleTable[1];

    results[l++] = pt1.$1;
    results[l++] = pt1.$2;

    var pt2 = center + angleTable[2];
    results[l++] = pt2.$1;
    results[l++] = pt2.$2;

    for (var j = 0; j < divisions - 3; j++) {
      results[l++] = origin.$1;
      results[l++] = origin.$2;
      results[l++] = pt2.$1;
      results[l++] = pt2.$2;

      pt2 = center + angleTable[j + 3];
      results[l++] = pt2.$1;
      results[l++] = pt2.$2;
    }
    return results;
  }

  static int computeDivisions(double scaledRadius) {
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

Matrix4 makeOrthograpgic(int width, int height) {
  var scale = Matrix4.identity()..scale(2.0 / width, - 2.0 / height, 0);
  var translate = Matrix4.identity()..translate(-1, 1.0, 0.5);
  return translate * scale;
}

class Canvas {
  Canvas(this._context, this._pass, this.width, this.height)
      : orthographic = makeOrthograpgic(width, height);

  final int width;
  final int height;
  final ContentContext _context;
  final RenderPass _pass;
  final Matrix4 orthographic;
  final List<Matrix4> transformStack = [
    Matrix4.identity(),
  ];

  void drawRect(
      double left, double top, double right, double bottom, RGBAColor color) {
    var hostData = Float32List(12);
    var offset = 0;
    hostData[offset++] = left;
    hostData[offset++] = top;
    hostData[offset++] = right;
    hostData[offset++] = top;
    hostData[offset++] = left;
    hostData[offset++] = bottom;

    hostData[offset++] = left;
    hostData[offset++] = bottom;
    hostData[offset++] = right;
    hostData[offset++] = top;
    hostData[offset++] = right;
    hostData[offset++] = bottom;

    var deviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: hostData.lengthInBytes);
    deviceBuffer.update(hostData);
    var view = deviceBuffer.asView();

    var uniformData = Float32List(24);
    offset = 0;
    var currentTransform = orthographic * transformStack.last;
    for (var i = 0; i < 16; i++) {
      uniformData[offset++] = currentTransform.storage[i];
    }

    uniformData[offset++] = color.$1;
    uniformData[offset++] = color.$2;
    uniformData[offset++] = color.$3;
    uniformData[offset++] = color.$4;

    var uniformDeviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: uniformData.lengthInBytes);
    uniformDeviceBuffer.update(uniformData);
    var uniformView = uniformDeviceBuffer.asView();

    var bindGroup = _context.context.createBindGroup(
        layout: _context.solidColorPipeline.$2,
        entries: [(binding: 0, resource: BufferBindGroup(uniformView))]);

    _pass.setPipeline(_context.solidColorPipeline.$1);
    _pass.setVertexBuffer(0, view);
    _pass.setBindGroup(0, bindGroup);
    _pass.draw(6);
  }

  void drawCircle(double x, double y, double radius, RGBAColor color) {
    var currentTransform = transformStack.last;
    var tessellateResults = Tessellator.tessellateCircle(
        x, y, radius, currentTransform.getMaxScaleOnAxis());
    var vertexCount = tessellateResults.length ~/ 2;

    var deviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: tessellateResults.lengthInBytes);
    deviceBuffer.update(tessellateResults);
    var view = deviceBuffer.asView();

    var uniformData = Float32List(24);
    var offset = 0;
    var appliedTransform = orthographic * currentTransform;
    for (var i = 0; i < 16; i++) {
      uniformData[offset++] = appliedTransform.storage[i];
    }

    uniformData[offset++] = color.$1;
    uniformData[offset++] = color.$2;
    uniformData[offset++] = color.$3;
    uniformData[offset++] = color.$4;

    var uniformDeviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: uniformData.lengthInBytes);
    uniformDeviceBuffer.update(uniformData);
    var uniformView = uniformDeviceBuffer.asView();

    var bindGroup = _context.context.createBindGroup(
        layout: _context.solidColorPipeline.$2,
        entries: [(binding: 0, resource: BufferBindGroup(uniformView))]);
    _pass.setVertexBuffer(0, view);
    _pass.setPipeline(_context.solidColorPipeline.$1);
    _pass.setBindGroup(0, bindGroup);
    _pass.draw(vertexCount);
  }

  void save() {
    var newMatrix = transformStack.last.clone();
    transformStack.add(newMatrix);
  }

  void restore() {
    if (transformStack.length == 1) {
      return;
    }
    transformStack.removeLast();
  }

  void translate(double dx, double dy) {
    transformStack.last.translate(dx, dy);
  }

  void scale(double dx, double dy) {
    transformStack.last.scale(dx, dy);
  }
}
