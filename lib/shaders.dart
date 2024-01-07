import 'browser.dart';
import 'wrapper.dart';

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
        primitiveTopology: PrimitiveTopology.triangles,
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
        primitiveTopology: PrimitiveTopology.triangleStrip,
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
