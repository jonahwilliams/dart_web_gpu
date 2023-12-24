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

  var onscreenTarget = await context.createOnscreen(canvas);
  var deviceBuffer =
      context.createDeviceBuffer(lengthInBytes: vertexBuffer.lengthInBytes);
  deviceBuffer.update(vertexBuffer);

  var pipeline = context.createRenderPipeline(
    module: context.createShaderModule(code: '''
    @vertex
    fn vertexMain(@location(0) pos: vec2f) ->
      @builtin(position) vec4f {
      return vec4f(pos, 0, 1);
    }

    @fragment
    fn fragmentMain() -> @location(0) vec4f {
      return vec4f(1, 0, 0, 1);
    }
  '''),
    label: 'Cell Shader',
    vertexEntrypoint: 'vertexMain',
    fragmentEntrypoint: 'fragmentMain',
    format: onscreenTarget.format,
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

  void render() {
    var commandBuffer =
        context.createCommandBuffer(label: 'Test Command buffer');
    var renderPass = commandBuffer.createRenderPass(
      label: 'Test Render Pass',
      attachments: [
        AttachmentDescriptor(
          clearColor: (0.0, 1.0, 0.0, 1.0),
          loadOp: LoadOP.clear,
          storeOp: StoreOp.store,
          renderTarget: onscreenTarget,
        )
      ],
    );
    for (var i = 0; i < 12; i++) {
      vertexBuffer[i] = math.Random().nextDouble();
    }
    deviceBuffer.update(vertexBuffer);

    renderPass.setPipeline(pipeline);
    renderPass.setVertexBuffer(0, deviceBuffer.asView());
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
