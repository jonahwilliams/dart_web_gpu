import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dart_web_gpu/browser.dart';

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
    }.jsify());

    return CanvasSwapchain._(canvasContext, canvas, selectedFormat);
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
            // TODO: other types
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

  GPURenderPipeline createRenderPipeline({
    String? label,
    required GPUShaderModule module,
    required String fragmentEntrypoint,
    required String vertexEntrypoint,
    required List<VertexLayoutDescriptor> layouts,
    required GPUPipelineLayout pipelineLayout,
    required TextureFormat format,
  }) {
    return _device.createRenderPipeline({
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
          },
        ],
      },
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
    String? label,
  }) {
    if (attachments.isEmpty) {
      throw Exception(
          'Invalid RenderPass description, required at least one attachment.');
    }

    return RenderPass._(_encoder.beginRenderPass({
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
          },
      ],
    }.jsify()));
  }

  void submit() {
    var commandBuffer = _encoder.finish();
    _device.queue.submit([commandBuffer].jsify());
  }
}

final class RenderPass {
  RenderPass._(this._renderPass);

  final GPURenderPass _renderPass;
  bool _debugIsEnded = false;

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
  });

  final GPUTexture texture;
  final TextureFormat format;
  final int width;
  final int height;

  GPUTextureView createView() {
    return texture.createView();
  }
}

final class CanvasSwapchain {
  CanvasSwapchain._(this._context, this._canvas, this.format);

  final GPUCanvasContext _context;
  final HTMLCanvas _canvas;

  /// The format of all render targets created by this swapchain.
  final TextureFormat format;

  RenderTarget createNext() {
    return RenderTarget(
      format: format,
      texture: _context.getCurrentTexture(),
      width: _canvas.width.toDartInt,
      height: _canvas.height.toDartInt,
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
