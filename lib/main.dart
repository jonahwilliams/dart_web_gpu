@staticInterop
import 'dart:js_interop';
import 'dart:typed_data';
import 'browser.dart';
import 'wrapper.dart';
import 'dart:math' as math;

void main(List<String> args) async {
  var canvas = document.getElementById('canvas'.toJS) as Canvas;
  canvas.width = 800.toJS;
  canvas.height = 800.toJS;
  final context = await Context.createContext();
  if (context == null) {
    return;
  }

  var vertexBuffer = Float32List.fromList([
    //   X,    Y,
    -0.8, -0.8, // Triangle 1 (Blue)
    0.8, -0.8,
    0.8, 0.8,

    -0.8, -0.8, // Triangle 2 (Red)
    0.8, 0.8,
    -0.8, 0.8,
  ]);

  var swapchain = await context.createSwapchain(canvas);
  var deviceBuffer =
      context.createDeviceBuffer(lengthInBytes: vertexBuffer.lengthInBytes);
  deviceBuffer.update(vertexBuffer);

  var bindGroupLayout = context.createBindGroupLayout(entries: [
    BindGroupLayoutEntry(
      visibility: GPUShaderStage.FRAGMENT,
      binding: 0,
      buffer: (
        hasDynamicOffset: false,
        minBindingSize: 0,
        type: BufferLayoutType.uniform,
      ),
    )
  ]);
  var pipelineLayout = context.createPipelineLayout(layouts: [bindGroupLayout]);

  var pipeline = context.createRenderPipeline(
    pipelineLayout: pipelineLayout,
    module: context.createShaderModule(code: '''
struct FragInfo {
  color: vec4f,
};

@group(0) @binding(0)
var<uniform> frag_info: FragInfo;

@vertex
fn vertexMain(@location(0) pos: vec2f) ->
  @builtin(position) vec4f {
  return vec4f(pos, 0, 1);
}

@fragment
fn fragmentMain() -> @location(0) vec4f {
  return frag_info.color;
}
  '''),
    label: 'Cell Shader',
    vertexEntrypoint: 'vertexMain',
    fragmentEntrypoint: 'fragmentMain',
    format: swapchain.format,
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

  var uniformBuffer = Float32List(16);
  uniformBuffer[0] = 0.9;
  uniformBuffer[1] = 0.5;
  uniformBuffer[2] = 0;
  uniformBuffer[3] = 1.0;
  var uniformDeviceBuffer =
      context.createDeviceBuffer(lengthInBytes: uniformBuffer.lengthInBytes);
  uniformDeviceBuffer.update(uniformBuffer);

  void render() {
    var onscreenTarget = swapchain.createNext();
    var commandBuffer =
        context.createCommandBuffer(label: 'Test Command buffer');
    var renderPass = commandBuffer.createRenderPass(
      label: 'Test Render Pass',
      attachments: [
        AttachmentDescriptor(
          clearColor: (0.0, 0.0, 0.0, 0.0),
          loadOp: LoadOP.clear,
          storeOp: StoreOp.store,
          renderTarget: onscreenTarget,
        )
      ],
    );

    var bindGroup = context.createBindGroup(layout: bindGroupLayout, entries: [
      (binding: 0, resource: BufferBindGroup(uniformDeviceBuffer.asView()))
    ]);

    // for (var i = 0; i < 12; i++) {
    //   vertexBuffer[i] = math.Random().nextDouble();
    // }
    // deviceBuffer.update(vertexBuffer);

    renderPass.setPipeline(pipeline);
    renderPass.setVertexBuffer(0, deviceBuffer.asView());
    renderPass.setBindGroup(0, bindGroup);
    renderPass.draw(6);

    renderPass.end();
    commandBuffer.submit();
    requestAnimationFrame((double _) {
      render();
    }.toJS);
  }

  requestAnimationFrame((double _) {
    render();
  }.toJS);
}
