// ignore_for_file: constant_identifier_names

@staticInterop
import 'dart:js_interop';

/// Minimal Browser Types ///

@JS()
@staticInterop
class Element {}

@JS()
@staticInterop
class Canvas extends Element {}

extension CanvasHelper on Canvas {
  external GPUCanvasContext getContext(JSString id);
}

extension Helper<T> on Future<T> {
  Future<S> cast<S>() => then((value) => value as S);
}

@JS()
@staticInterop
class Document {}

extension DocumentHelpers on Document {
  @JS()
  @staticInterop
  external Element getElementById(JSString id);
}

@JS()
@staticInterop
external Document get document;

@JS()
@staticInterop
external Navigator get navigator;

@JS()
@staticInterop
class Navigator {}

extension NavigatorHelpers on Navigator {
  external GPUContext? get gpu;
}

@JS()
@staticInterop
external void requestAnimationFrame(JSFunction value);

/// GPU Types ///

@JS()
@staticInterop
class GPUCanvasContext {}

extension GPUCanvasContextHelpers on GPUCanvasContext {
  external void configure(JSAny? args);

  external GPUTexture getCurrentTexture();
}

@JS()
@staticInterop
class GPUTexture {}

extension GPUTextureHelpers on GPUTexture {
  external GPUTextureView createView([JSAny? args]);
}

@JS()
@staticInterop
class GPUTextureView {}

extension ElementHelpers on Element {
  external JSNumber width;

  external JSNumber height;
}

@JS()
@staticInterop
class GPUContext {}

extension GPUContextHelpers on GPUContext {
  external JSPromise requestAdapter();

  Future<GPUAdapter?> fetchAdapter() async {
    return requestAdapter().toDart.cast<GPUAdapter?>();
  }

  external JSString getPreferredCanvasFormat();
}

@JS()
@staticInterop
class GPUAdapter {}

extension GPUAdapterHelpers on GPUAdapter {
  external JSPromise requestDevice();

  Future<GPUDevice?> fetchDevice() async {
    return requestDevice().toDart.cast<GPUDevice?>();
  }
}

@JS()
@staticInterop
class GPUDevice {}

extension GPUDeviceHelpers on GPUDevice {
  external GPUShaderModule createShaderModule(JSAny? map);

  external GPURenderPipeline createRenderPipeline(JSAny? map);

  external GPUCommandEncoder createCommandEncoder(JSAny? map);

  external GPUDeviceQueue get queue;

  /// Create a new GPU buffer.
  ///
  /// keys:
  ///
  ///   [size]: The size of the buffer in bytes.
  ///
  ///   [usage]: A [GPUBufferUsage] flag.
  ///
  ///   [mappedAtCreation]: If true creates the buffer in an already mapped state,
  ///   allowing getMappedRange() to be called immediately. It is valid to set
  ///   mappedAtCreation to true even if usage does not contain MAP_READ or MAP_WRITE.
  ///   This can be used to set the buffer’s initial data.
  external GPUBuffer createBuffer(JSAny? map);
}

abstract class GPUBufferUsage {
  /// The buffer can be mapped for reading. (Example: calling mapAsync() with GPUMapMode.READ)
  ///
  /// May only be combined with COPY_DST.
  static const int MAP_READ = 0x0001;

  /// The buffer can be mapped for writing. (Example: calling mapAsync() with GPUMapMode.WRITE)
  ///
  /// May only be combined with COPY_SRC.
  static const int MAP_WRITE = 0x0002;

  /// The buffer can be used as the source of a copy operation.
  ///
  /// (Examples: as the source argument of a copyBufferToBuffer() or copyBufferToTexture() call.)
  static const int COPY_SRC = 0x0004;
  static const int COPY_DST = 0x0008;
  static const int INDEX = 0x0010;
  static const int VERTEX = 0x0020;
  static const int UNIFORM = 0x0040;
  static const int STORAGE = 0x0080;
  static const int INDIRECT = 0x0100;
  static const int QUERY_RESOLVE = 0x0200;
}

@JS()
@staticInterop
class GPUCommandEncoder {}

extension GPUCommandEncoderHelpers on GPUCommandEncoder {
  external GPURenderPass beginRenderPass(JSAny? map);

  external GPUCommandBuffer finish();
}

@JS()
@staticInterop
class GPURenderPass {}

@JS()
@staticInterop
class GPUBuffer {}

extension GPUBufferHelpers on GPUBuffer {
  external JSArrayBuffer getMappedRange([JSNumber offset, JSNumber size]);

  external void unmap();
}

typedef GPUIndexFormat = JSString;

extension GPURenderPassHelpers on GPURenderPass {
  external void setPipeline(GPURenderPipeline pipeline);

  external void setIndexBuffer(GPUBuffer buffer, GPUIndexFormat indexFormat,
      [JSNumber? offset, JSNumber? size]);

  external void setVertexBuffer(JSNumber slot, GPUBuffer? buffer,
      [JSNumber? offset, JSNumber? size]);

  external void draw(JSNumber vertexCount,
      [JSNumber? instanceCount,
      JSNumber? firstVertex,
      JSNumber? firstInstance]);

  external void drawIndexed(JSNumber indexCount,
      [JSNumber? instanceCount,
      JSNumber? firstIndex,
      JSNumber? baseVertex,
      JSNumber? firstInstance]);

  external void drawIndirect(GPUBuffer indirectBuffer, JSNumber indirectOffset);

  external void drawIndexedIndirect(
      GPUBuffer indirectBuffer, JSNumber indirectOffset);

  external void end();
}

@JS()
@staticInterop
class GPUShaderModule {}

@JS()
@staticInterop
class GPURenderPipeline {}

@JS()
@staticInterop
class GPUCommandBuffer {}

@JS()
@staticInterop
class GPUDeviceQueue {}

extension GPUDeviceQueueHelpers on GPUDeviceQueue {
  external void submit(JSAny? buffers);

  external void writeBuffer(GPUBuffer buffer, JSNumber offset, JSAny data);
}
