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

final class DeviceBuffer {
  DeviceBuffer._(this._device, this._buffer, this.lengthInBytes);

  final GPUDevice _device;
  final GPUBuffer _buffer;
  final int lengthInBytes;

  void update(Float32List data, {int offset = 0}) {
    assert(data.length <= lengthInBytes);
    assert(data.length + offset <= lengthInBytes);
    _device.queue.writeBuffer(_buffer, offset.toJS, data.toJS);
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

  Future<RenderTarget> createOnscreen(Canvas canvas) async {
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

    return OnscreenRenderTarget._(canvas, canvasContext, selectedFormat);
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

  GPURenderPipeline createRenderPipeline({
    String? label,
    required GPUShaderModule module,
    required String fragmentEntrypoint,
    required String vertexEntrypoint,
    required List<VertexLayoutDescriptor> layouts,
    required TextureFormat format,
  }) {
    return _device.createRenderPipeline({
      'label': label,
      'layout': 'auto',
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

abstract base class RenderTarget {
  const RenderTarget();

  TextureFormat get format;
  int get width;
  int get height;

  GPUTextureView createView();
}

final class OffscreenRenderTarget extends RenderTarget {
  const OffscreenRenderTarget({
    required this.texture,
    required this.format,
    required this.width,
    required this.height,
  });

  final GPUTexture texture;
  @override
  final TextureFormat format;
  @override
  final int width;
  @override
  final int height;

  @override
  GPUTextureView createView() {
    return texture.createView();
  }
}

// This class is sort of magic and mixes the render target with a swapchain.
// This logic  should probably be split into a swapchain class, so that
// multiple references to the onscreen target work correctly.
final class OnscreenRenderTarget extends RenderTarget {
  const OnscreenRenderTarget._(this._canvas, this._context, this.format);

  final GPUCanvasContext _context;
  final Canvas _canvas;

  @override
  final TextureFormat format;

  @override
  GPUTextureView createView() {
    return _context.getCurrentTexture().createView();
  }

  @override
  int get height => _canvas.width.toDartInt;

  @override
  int get width => _canvas.height.toDartInt;
}
