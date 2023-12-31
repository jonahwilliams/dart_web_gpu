import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dart_web_gpu/browser.dart';

import 'types.dart';

/// This library provides wrappers over the browser WebGPU types to allow the APIs to be
/// more Dart-y and high level. many of the record types are just placeholders.

typedef VertexLayoutDescriptor = ({
  int arrayStride,
  List<VertexLayoutAttribute> attributes
});

typedef VertexLayoutAttribute = ({
  ShaderType format,
  int offset,
  int shaderLocation
});

enum ShaderType {
  float32x2,
}

class BindGroupLayoutEntry {
  const BindGroupLayoutEntry({
    required this.binding,
    required this.visibility,
    this.buffer,
    this.externalTexture,
    this.sampler,
    this.storageTexture,
    this.texture,
  });

  /// The binding number that matches the value declared on the resource in the shader.
  final int binding;

  /// One or more of the GPUShaderStage flags.
  final int visibility;

  /// Exactly one of the following objects must be defined. Sorry, the API
  /// is weird.
  final BufferLayoutObject? buffer;
  final ExternalTextureLayoutObject? externalTexture;
  final SamplerLayoutObject? sampler;
  final StorageTextureLayoutObject? storageTexture;
  final TextureLayoutObject? texture;
}

typedef BufferLayoutObject = ({
  bool? hasDynamicOffset,
  int? minBindingSize,
  BufferLayoutType? type,
});

typedef ExternalTextureLayoutObject = ();

enum BufferLayoutType {
  readOnlyStorage,
  storage,
  uniform,
}

typedef SamplerLayoutObject = ();

enum SamplerLayoutType {
  comparison,
  filtering,
  nonFiltering,
}

typedef StorageTextureLayoutObject = ();
typedef TextureLayoutObject = ({
  bool? multisampled,
});

extension BufferLayoutTypeHelpers on BufferLayoutType {
  String toGPUString() {
    switch (this) {
      case BufferLayoutType.readOnlyStorage:
        return 'read-only-storage';
      case BufferLayoutType.storage:
      case BufferLayoutType.uniform:
        return name;
    }
  }
}

extension SamplerLayoutTypeHelpers on SamplerLayoutType {
  String toGPUString() {
    switch (this) {
      case SamplerLayoutType.nonFiltering:
        return 'non-filtering';
      case SamplerLayoutType.comparison:
      case SamplerLayoutType.filtering:
        return name;
    }
  }
}

enum ResourceLayoutObject {
  buffer,
  externalTexture,
  sampler,
  storageTexture,
  texture,
}

enum SampleCount {
  one,
  four,
}

enum AddressMode {
  /// The texture coordinates are clamped between 0.0 and 1.0, inclusive.
  clampToEdge,

  /// The texture coordinates wrap to the other side of the texture.
  repeat,

  /// The texture coordinates wrap to the other side of the texture, but the texture is flipped when the integer part of the coordinate is odd
  mirrorRepeat,

  /// WHERE IS CLAMP TO BORDER?
}

extension on AddressMode {
  String toGPUString() {
    switch (this) {
      case AddressMode.clampToEdge:
        return 'clamp-to-edge';
      case AddressMode.repeat:
        return 'repeat';
      case AddressMode.mirrorRepeat:
        return 'mirror-repeat';
    }
  }
}

enum MagFitler {
  /// Return the value of the texel nearest to the texture coordinates.
  nearest,

  /// Select two texels in each dimension and return a linear interpolation between their values.
  linear,
}

final class DeviceBuffer {
  DeviceBuffer._(this._device, this._buffer, this.lengthInBytes);

  final GPUDevice _device;
  final GPUBuffer _buffer;
  final int lengthInBytes;

  void update(TypedData data, {int offset = 0}) {
    assert(data.lengthInBytes <= lengthInBytes);
    assert(data.lengthInBytes + offset <= lengthInBytes);
    _device.queue.writeBuffer(_buffer, offset.toJS, data.buffer.toJS);
  }

  static const int kWholeSize = -1;

  BufferView asView({int offset = 0, int size = kWholeSize}) {
    assert(size >= 0 || size == kWholeSize);
    return BufferView._(
        this, offset, size == kWholeSize ? lengthInBytes : size);
  }
}

final class BufferView {
  const BufferView._(this.buffer, this.offset, this.size);

  final DeviceBuffer buffer;
  final int offset;
  final int size;
}

final class Context {
  Context._(this._device);

  final GPUDevice _device;

  static Future<Context?> createContext() async {
    if (navigator.gpu == null) {
      return null;
    }
    var adapter = await navigator.gpu!.fetchAdapter();
    var device = await adapter?.fetchDevice();
    if (device == null) {
      return null;
    }
    return Context._(device);
  }

  GPUShaderModule createShaderModule({
    String? label,
    required String code,
  }) {
    return _device.createShaderModule({'label': label, 'code': code}.jsify());
  }

  CommandBuffer createCommandBuffer({
    String? label,
  }) {
    return CommandBuffer._(_device, label);
  }

  GPUBindGroup createBindGroup({
    String? label,
    required GPUBindGroupLayout layout,
    required List<({int binding, BindGroupResource resource})> entries,
  }) {
    return _device.createBindGroup({
      'label': label?.toJS,
      'layout': layout,
      'entries': [
        for (var entry in entries)
          {
            'binding': entry.binding,
            'resource': entry.resource.toJS(),
          },
      ],
    }.jsify());
  }

  Future<CanvasSwapchain> createSwapchain(HTMLCanvas canvas) async {
    var canvasContext = canvas.getContext('webgpu'.toJS);
    var preferredFormat = navigator.gpu!.getPreferredCanvasFormat().toDart;
    TextureFormat selectedFormat = TextureFormat.bgra8unorm;
    for (var format in TextureFormat.values) {
      if (format.name == preferredFormat) {
        selectedFormat = format;
        break;
      }
    }

    canvasContext.configure({
      'device': _device,
      'format': selectedFormat.name,
      'alphaMode': 'premultiplied',
      'colorspace': 'srgb',
      'usage': GPUTextureUsage.RENDER_ATTACHMENT,
    }.jsify());

    return CanvasSwapchain._(
      canvasContext,
      canvas,
      selectedFormat,
      this,
    );
  }

  DeviceBuffer createDeviceBuffer({
    required int lengthInBytes,
    int usage = GPUBufferUsage.VERTEX |
        GPUBufferUsage.COPY_DST |
        GPUBufferUsage.INDEX |
        GPUBufferUsage.UNIFORM,
  }) {
    var buffer = _device.createBuffer({
      'size': lengthInBytes,
      'usage': usage,
    }.jsify());
    return DeviceBuffer._(_device, buffer, lengthInBytes);
  }

  GPUBindGroupLayout createBindGroupLayout({
    String? label,
    required List<BindGroupLayoutEntry> entries,
  }) {
    return _device.createBindGroupLayout({
      'label': label,
      'entries': [
        for (var entry in entries)
          {
            'binding': entry.binding,
            'visibility': entry.visibility,
            if (entry.buffer != null)
              'buffer': {
                'hasDynamicOffset': entry.buffer!.hasDynamicOffset ?? false,
                'minBindingSize': entry.buffer!.minBindingSize ?? 0,
                'type': (entry.buffer!.type ?? BufferLayoutType.uniform)
                    .toGPUString(),
              },
            if (entry.sampler != null)
              'sampler': {
                'type': 'filtering',
              },
            if (entry.texture != null)
              'texture': {
                'multisampled': false,
                'sampleType': 'float',
              },
          },
      ],
    }.jsify());
  }

  GPUPipelineLayout createPipelineLayout({
    String? label,
    required List<GPUBindGroupLayout> layouts,
  }) {
    return _device.createPipelineLayout({
      'label': label,
      'bindGroupLayouts': layouts,
    }.jsify());
  }

  GPURenderPipeline createRenderPipeline(
      {String? label,
      required GPUShaderModule module,
      required String fragmentEntrypoint,
      required String vertexEntrypoint,
      required List<VertexLayoutDescriptor> layouts,
      required GPUPipelineLayout pipelineLayout,
      required TextureFormat format,
      required SampleCount sampleCount,
      required BlendMode blendMode}) {
    var data = {
      'label': label,
      'layout': pipelineLayout,
      'vertex': {
        'module': module,
        'entryPoint': vertexEntrypoint,
        'buffers': [
          for (var layout in layouts)
            {
              'arrayStride': layout.arrayStride,
              'attributes': [
                for (var attr in layout.attributes)
                  {
                    'format': attr.format.name,
                    'offset': attr.offset,
                    'shaderLocation': attr.shaderLocation,
                  },
              ],
            },
        ],
      },
      'fragment': {
        'module': module,
        'entryPoint': fragmentEntrypoint,
        'targets': [
          {
            'format': format.name,
            'blend': {
              'alpha': {
                'operation': blendMode.alphaOp.name,
                'srcFactor': blendMode.srcAlphaBlendFactor.toGPUString(),
                'dstFactor': blendMode.dstAlphaBlendFactor.toGPUString(),
              },
              'color': {
                'operation': blendMode.colorOp.name,
                'srcFactor': blendMode.srcColorBlendFactor.toGPUString(),
                'dstFactor': blendMode.dstColorBlendFactor.toGPUString(),
              },
            }
          },
        ],
      },
      'multisample': {
        'count': sampleCount == SampleCount.one ? '1' : '4',
      }
    };
    return _device.createRenderPipeline(data.jsify());
  }

  GPUSampler createSampler({
    required AddressMode addressModeWidth,
    required AddressMode addressModeHeight,
    required MagFitler magFitler,
  }) {
    return _device.createSampler({
      'addressModeU': addressModeWidth.toGPUString(),
      'addressModeV': addressModeHeight.toGPUString(),
    }.jsify());
  }

  GPUTexture createTexture({
    required TextureFormat format,
    required SampleCount sampleCount,
    required int width,
    required int height,
    required int usage,
  }) {
    return _device.createTexture({
      'size': [width, height],
      'sampleCount': sampleCount == SampleCount.one ? 1 : 4,
      'format': format.name,
      'usage': usage,
    }.jsify());
  }
}

typedef RGBAColor = (double, double, double, double);

enum LoadOP {
  /// Retain the existing contents of the texture.
  load,

  /// Clear the texture to a clear color before rendering.
  clear,
}

enum StoreOp {
  store,
  discard,
}

final class AttachmentDescriptor {
  /// Create a new [AttachmentDescriptor].
  const AttachmentDescriptor({
    this.clearColor = (0, 0, 0, 0),
    required this.loadOp,
    required this.storeOp,
    required this.renderTarget,
  });

  /// The color to clear the texture to, if the [loadOp] is set to clear.
  ///
  /// If not provided, defaults to transparent black.
  final RGBAColor clearColor;
  final LoadOP loadOp;
  final StoreOp storeOp;
  final RenderTarget renderTarget;
}

final class CommandBuffer {
  CommandBuffer._(this._device, String? label)
      : _encoder = _device.createCommandEncoder({'label': label}.jsify());

  final GPUDevice _device;
  final GPUCommandEncoder _encoder;

  RenderPass createRenderPass({
    required List<AttachmentDescriptor> attachments,
    required Size size,
    String? label,
  }) {
    if (attachments.isEmpty) {
      throw Exception(
          'Invalid RenderPass description, required at least one attachment.');
    }

    return RenderPass._(
      _encoder.beginRenderPass({
        'label': label,
        'colorAttachments': [
          for (var desc in attachments)
            {
              'clearValue': [
                desc.clearColor.$1,
                desc.clearColor.$2,
                desc.clearColor.$3,
                desc.clearColor.$4
              ],
              'loadOp': desc.loadOp.name,
              'storeOp': desc.storeOp.name,
              'view': desc.renderTarget.createView(),
              if (desc.renderTarget.resolve != null)
                'resolveTarget': desc.renderTarget.resolve!.createView(),
            },
        ],
      }.jsify()),
      size,
      attachments,
    );
  }

  void submit() {
    var commandBuffer = _encoder.finish();
    _device.queue.submit([commandBuffer].jsify());
  }
}

final class RenderPass {
  RenderPass._(this._renderPass, this.size, this._attachments);

  final Size size;
  final GPURenderPass _renderPass;
  final List<AttachmentDescriptor> _attachments;
  bool _debugIsEnded = false;

  AttachmentDescriptor getColorAttachment() {
    return _attachments.single;
  }

  void setPipeline(GPURenderPipeline pipeline) {
    assert(!_debugIsEnded);
    _renderPass.setPipeline(pipeline);
  }

  void setVertexBuffer(int slot, BufferView bufferView) {
    assert(!_debugIsEnded);
    _renderPass.setVertexBuffer(slot.toJS, bufferView.buffer._buffer,
        bufferView.offset.toJS, bufferView.size.toJS);
  }

  void setBindGroup(int binding, GPUBindGroup group) {
    _renderPass.setBindGroup(binding.toJS, group);
  }

  void draw(int vertexCount) {
    assert(!_debugIsEnded);
    assert(vertexCount > 0);
    _renderPass.draw(vertexCount.toJS);
  }

  /// End the current render pass.
  void end() {
    assert(!_debugIsEnded);
    assert(() {
      _debugIsEnded = true;
      return true;
    }());
    _renderPass.end();
  }
}

enum TextureFormat {
  bgra8unorm,
  rgba8unorm,
}

final class RenderTarget {
  const RenderTarget({
    required this.texture,
    required this.format,
    required this.width,
    required this.height,
    required this.resolve,
  });

  final GPUTexture texture;
  final GPUTexture? resolve;
  final TextureFormat format;
  final int width;
  final int height;

  GPUTextureView createView() {
    return texture.createView();
  }

  void dispose() {
    texture.destroy();
    resolve?.destroy();
  }
}

final class CanvasSwapchain {
  CanvasSwapchain._(
    this._canvasContext,
    this._canvas,
    this.format,
    this._context,
  );

  final GPUCanvasContext _canvasContext;
  final HTMLCanvas _canvas;
  final Context _context;

  /// The format of all render targets created by this swapchain.
  final TextureFormat format;

  RenderTarget createNext() {
    var width = _canvas.width.toDartInt;
    var height = _canvas.height.toDartInt;
    final GPUTexture msaaTex = _context.createTexture(
      width: width,
      height: height,
      sampleCount: SampleCount.four,
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
      format: format,
    );
    return RenderTarget(
      format: format,
      texture: msaaTex,
      resolve: _canvasContext.getCurrentTexture(),
      width: width,
      height: height,
    );
  }
}

abstract base class BindGroupResource {
  const BindGroupResource();

  JSAny? toJS();
}

final class BufferBindGroup extends BindGroupResource {
  const BufferBindGroup(this.view);

  final BufferView view;

  @override
  JSAny? toJS() {
    return {
      'buffer': view.buffer._buffer,
      'offset': view.offset,
      'size': view.size,
    }.jsify();
  }
}

final class SamplerBindGroup extends BindGroupResource {
  const SamplerBindGroup(this.sampler);

  final GPUSampler sampler;

  @override
  JSAny? toJS() {
    return sampler.jsify();
  }
}

final class TextureBindGroup extends BindGroupResource {
  const TextureBindGroup(this.textureView);

  final GPUTextureView textureView;

  @override
  JSAny? toJS() {
    return textureView.jsify();
  }
}

enum BlendMode {
  clear(BlendOperation.add, BlendOperation.add, BlendFactor.zero,
      BlendFactor.zero, BlendFactor.zero, BlendFactor.zero),
  src(BlendOperation.add, BlendOperation.add, BlendFactor.zero,
      BlendFactor.zero, BlendFactor.one, BlendFactor.one),
  dst(BlendOperation.add, BlendOperation.add, BlendFactor.one, BlendFactor.one,
      BlendFactor.zero, BlendFactor.zero),

  srcOver(
    BlendOperation.add,
    BlendOperation.add,
    BlendFactor.oneMinusSrcAlpha,
    BlendFactor.oneMinusSrcAlpha,
    BlendFactor.one,
    BlendFactor.one,
  );

  // Not added yet.
  // dst(BlendOperation.add, BlendFactor.zero, BlendFactor.zero),
  // srcOver(BlendOperation.add, BlendFactor.zero, BlendFactor.zero),
  // dstOver(BlendOperation.add, BlendFactor.zero, BlendFactor.zero),
  // srcIn(BlendOperation.add, BlendFactor.zero, BlendFactor.zero),
  // dstIn(BlendOperation.add, BlendFactor.zero, BlendFactor.zero),
  // srcOut(BlendOperation.add, BlendFactor.zero, BlendFactor.zero),
  // dstOut(BlendOperation.add, BlendFactor.zero, BlendFactor.zero),
  // srcATop(BlendOperation.add, BlendFactor.zero, BlendFactor.zero),
  // dstATop(BlendOperation.add, BlendFactor.zero, BlendFactor.zero),
  // xor(BlendOperation.add, BlendFactor.zero, BlendFactor.zero),
  // plus(BlendOperation.add, BlendFactor.zero, BlendFactor.zero),
  // modulate(BlendOperation.add, BlendFactor.zero, BlendFactor.zero);

  const BlendMode(
      this.colorOp,
      this.alphaOp,
      this.dstAlphaBlendFactor,
      this.dstColorBlendFactor,
      this.srcAlphaBlendFactor,
      this.srcColorBlendFactor);

  final BlendOperation colorOp;
  final BlendOperation alphaOp;
  final BlendFactor dstAlphaBlendFactor;
  final BlendFactor dstColorBlendFactor;
  final BlendFactor srcAlphaBlendFactor;
  final BlendFactor srcColorBlendFactor;
}

enum BlendFactor {
  zero,
  one,
  src,
  oneMinusSrc,
  srcAlpha,
  oneMinusSrcAlpha,
  dst,
  oneMinusDst,
  dstAlpha,
  oneMinusDstAlpha,
  srcAlphaSaturated,
  constant,
  oneMinusConstant,
}

extension on BlendFactor {
  String toGPUString() {
    switch (this) {
      case BlendFactor.zero:
        return 'zero';
      case BlendFactor.one:
        return 'one';
      case BlendFactor.src:
        return 'src';
      case BlendFactor.oneMinusSrc:
        return 'one-minus-src';
      case BlendFactor.srcAlpha:
        return 'src-alpha';
      case BlendFactor.oneMinusSrcAlpha:
        return 'one-minus-src-alpha';
      case BlendFactor.dst:
        return 'dst';
      case BlendFactor.oneMinusDst:
        return 'one-minus-dst';
      case BlendFactor.dstAlpha:
        return 'dst-alpha';
      case BlendFactor.oneMinusDstAlpha:
        return 'one-minus-dst-alpha';
      case BlendFactor.srcAlphaSaturated:
        return 'src-alpha-saturated';
      case BlendFactor.constant:
        return 'constant';
      case BlendFactor.oneMinusConstant:
        return 'one-minus-constant';
    }
  }
}

enum BlendOperation {
  add,
  subtract,
}
