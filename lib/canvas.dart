import 'dart:typed_data';

import 'browser.dart';
import 'wrapper.dart';
import 'package:vector_math/vector_math.dart';
import 'dart:math' as math;

typedef PipelineAndLayout = (GPURenderPipeline, GPUBindGroupLayout);

class ContentContext {
  ContentContext(this.context, this._format) {
    _initSolidColor(_format);
    _initTexture(_format);
  }

  final TextureFormat _format;
  final Context context;

  RenderTarget createOffscreenTarget({
    required int width,
    required int height,
  }) {
    var msaaTex = context.createTexture(
      format: _format,
      sampleCount: SampleCount.four,
      width: width,
      height: height,
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
    );
    var resolveTex = context.createTexture(
      format: _format,
      sampleCount: SampleCount.one,
      width: width,
      height: height,
      usage:
          GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
    );
    return RenderTarget(
        texture: msaaTex,
        format: _format,
        width: width,
        height: height,
        resolve: resolveTex);
  }

  final Map<BlendMode, PipelineAndLayout> _solidColorPipeline =
      <BlendMode, PipelineAndLayout>{};
  final Map<BlendMode, PipelineAndLayout> _textureFillPipeline =
      <BlendMode, PipelineAndLayout>{};

  PipelineAndLayout getSolidColorPipeline({
    required BlendMode blendMode,
  }) {
    return _solidColorPipeline[blendMode]!;
  }

  PipelineAndLayout getTextureFillPipeline({
    required BlendMode blendMode,
  }) {
    return _textureFillPipeline[blendMode]!;
  }

  void _initTexture(TextureFormat format) {
    var bindGroupLayout = context.createBindGroupLayout(entries: [
      BindGroupLayoutEntry(
        visibility: GPUShaderStage.FRAGMENT | GPUShaderStage.VERTEX,
        binding: 0,
        buffer: (
          hasDynamicOffset: false,
          minBindingSize: 0,
          type: BufferLayoutType.uniform,
        ),
      ),
      BindGroupLayoutEntry(
        visibility: GPUShaderStage.FRAGMENT,
        binding: 1,
        texture: (multisampled: false),
      ),
      BindGroupLayoutEntry(
        visibility: GPUShaderStage.FRAGMENT,
        binding: 2,
        sampler: (),
      ),
    ]);
    var pipelineLayout =
        context.createPipelineLayout(layouts: [bindGroupLayout]);
    var module = context.createShaderModule(code: '''
struct UniformData {
  mvp: mat4x4<f32>,
  alpha: f32,
};

@group(0) @binding(0)
var<uniform> uniform_data: UniformData;

@group(0) @binding(1)
var texture0: texture_2d<f32>;

@group(0) @binding(2)
var sampler0: sampler;

struct VertexOut {
  @builtin(position) position: vec4f,
  @location(1) uvs: vec2f,
};

@vertex
fn vertexMain(@location(0) pos: vec2f, @location(1) uvs: vec2f) ->
  VertexOut {
  var out: VertexOut;
  out.position = uniform_data.mvp * vec4f(pos, 0, 1);
  out.uvs = uvs;
  return out;
}

@fragment
fn fragmentMain(in: VertexOut) -> @location(0) vec4f {
  return textureSample(texture0, sampler0, in.uvs) * uniform_data.alpha;
}
  ''');

    for (var mode in BlendMode.values) {
      var pipeline = context.createRenderPipeline(
        pipelineLayout: pipelineLayout,
        sampleCount: SampleCount.four,
        blendMode: mode,
        module: module,
        label: 'Texture Shader ${mode.name}',
        vertexEntrypoint: 'vertexMain',
        fragmentEntrypoint: 'fragmentMain',
        format: format,
        layouts: [
          (
            arrayStride: 16,
            attributes: [
              (
                format: ShaderType.float32x2,
                offset: 0,
                shaderLocation: 0,
              ),
              (
                format: ShaderType.float32x2,
                offset: 8,
                shaderLocation: 1,
              )
            ],
          ),
        ],
      );
      _textureFillPipeline[mode] = (pipeline, bindGroupLayout);
    }
  }

  void _initSolidColor(TextureFormat format) {
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
    var module = context.createShaderModule(code: '''
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
  ''');

    for (var mode in BlendMode.values) {
      var pipeline = context.createRenderPipeline(
        pipelineLayout: pipelineLayout,
        sampleCount: SampleCount.four,
        blendMode: mode,
        module: module,
        label: 'Rect Shader ${mode.name}',
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
      _solidColorPipeline[mode] = (pipeline, bindGroupLayout);
    }
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
  var scale = Matrix4.identity()..scale(2.0 / width, -2.0 / height, 0);
  var translate = Matrix4.identity()..translate(-1, 1.0, 0.5);
  return translate * scale;
}

class _CanvasStack {
  _CanvasStack(this.pass, this.transform,
      [this.saveLayer, this.buffer, this.bounds]);

  final RenderPass pass;
  final CommandBuffer? buffer;
  final Matrix4 transform;
  final Paint? saveLayer;
  final (double, double, double, double)? bounds;
}

class Canvas {
  Canvas(this._context, RenderPass pass, this.width, this.height)
      : orthographic = makeOrthograpgic(width, height),
        _stack = [_CanvasStack(pass, Matrix4.identity())];

  final int width;
  final int height;
  final ContentContext _context;
  final Matrix4 orthographic;
  final List<_CanvasStack> _stack;

  void drawRect(
      double left, double top, double right, double bottom, Paint paint) {
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
    var currentTransform = orthographic * _stack.last.transform;
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

    var pass = _stack.last.pass;
    pass.setPipeline(pipeline.$1);
    pass.setVertexBuffer(0, view);
    pass.setBindGroup(0, bindGroup);
    pass.draw(6);
  }

  void drawCircle(double x, double y, double radius, Paint paint) {
    var currentTransform = _stack.last.transform;
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

    var pass = _stack.last.pass;
    pass.setVertexBuffer(0, view);
    pass.setPipeline(pipeline.$1);
    pass.setBindGroup(0, bindGroup);
    pass.draw(vertexCount);
  }

  void drawTexture(double left, double top, double right, double bottom,
      Paint paint, GPUTextureView textureView) {
    var hostData = Float32List(24);
    var offset = 0;
    hostData[offset++] = left;
    hostData[offset++] = top;
    hostData[offset++] = 0;
    hostData[offset++] = 0;

    hostData[offset++] = right;
    hostData[offset++] = top;
    hostData[offset++] = 1;
    hostData[offset++] = 0;

    hostData[offset++] = left;
    hostData[offset++] = bottom;
    hostData[offset++] = 0;
    hostData[offset++] = 1;

    hostData[offset++] = left;
    hostData[offset++] = bottom;
    hostData[offset++] = 0;
    hostData[offset++] = 1;

    hostData[offset++] = right;
    hostData[offset++] = top;
    hostData[offset++] = 1;
    hostData[offset++] = 0;

    hostData[offset++] = right;
    hostData[offset++] = bottom;
    hostData[offset++] = 1;
    hostData[offset++] = 1;

    var deviceBuffer = _context.context
        .createDeviceBuffer(lengthInBytes: hostData.lengthInBytes);
    deviceBuffer.update(hostData);
    var view = deviceBuffer.asView();

    var uniformData = Float32List(24);
    offset = 0;
    var currentTransform = orthographic * _stack.last.transform;
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

    var pass = _stack.last.pass;
    pass.setPipeline(pipeline.$1);
    pass.setVertexBuffer(0, view);
    pass.setBindGroup(0, bindGroup);
    pass.draw(6);
  }

  void save() {
    var newMatrix = _stack.last.transform.clone();
    _stack.add(_CanvasStack(_stack.last.pass, newMatrix, null, null));
  }

  void restore() {
    if (_stack.length == 1) {
      throw Exception();
    }
    var last = _stack.removeLast();
    if (last.saveLayer != null) {
      last.pass.end();
      last.buffer!.submit();
      var renderTarget = last.pass.getColorAttachment().renderTarget;
      drawTexture(last.bounds!.$1, last.bounds!.$2, last.bounds!.$3,
          last.bounds!.$4, last.saveLayer!, renderTarget.resolve!.createView());
      //renderTarget.dispose();
    }
  }

  void translate(double dx, double dy) {
    _stack.last.transform.translate(dx, dy);
  }

  void scale(double dx, double dy) {
    _stack.last.transform.scale(dx, dy);
  }

  void saveLayer(double l, double t, double r, double b, Paint paint) {
    var newMatrix = _stack.last.transform.clone();

    var width = (r - l).ceil();
    var height = (b - t).ceil();

    var commandBuffer =
        _context.context.createCommandBuffer(label: 'Save Layer');
    var renderPass = commandBuffer.createRenderPass(
      label: 'Offscreen Render Pass',
      attachments: [
        AttachmentDescriptor(
          clearColor: (0.0, 0.0, 0.0, 0.0),
          loadOp: LoadOP.clear,
          storeOp: StoreOp.discard,
          renderTarget:
              _context.createOffscreenTarget(width: width, height: height),
        )
      ],
    );

    _stack.add(_CanvasStack(
        renderPass, newMatrix, paint, commandBuffer, (l, t, r, b)));
  }


  void dispose() {

  }
}

class Paint {
  RGBAColor color = (0, 0, 0, 0);
  BlendMode mode = BlendMode.srcOver;
}
