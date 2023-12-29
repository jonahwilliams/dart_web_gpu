@staticInterop
import 'dart:js_interop';
import 'package:dart_web_gpu/canvas.dart';

import 'browser.dart';
import 'wrapper.dart';

void main(List<String> args) async {
  var canvas = document.getElementById('canvas'.toJS) as HTMLCanvas;
  canvas.width = 800.toJS;
  canvas.height = 800.toJS;
  final context = await Context.createContext();
  if (context == null) {
    return;
  }
  var swapchain = await context.createSwapchain(canvas);
  final contentContext = ContentContext(context, swapchain.format);

  void render() {
    var onscreenTarget = swapchain.createNext();
    var commandBuffer =
        context.createCommandBuffer(label: 'Test Command buffer');

    var renderPass = commandBuffer.createRenderPass(
      label: 'Test Render Pass',
      attachments: [
        AttachmentDescriptor(
          clearColor: (1.0, 0.0, 0.0, 1.0),
          loadOp: LoadOP.clear,
          storeOp: StoreOp.discard,
          renderTarget: onscreenTarget,
        )
      ],
    );
    var canvas = Canvas(contentContext, renderPass, 800, 800);

    canvas.saveLayer(0, 0, 400, 400, Paint()..color = (0, 0, 0, 0.5));
    canvas.drawRect(0, 0, 100, 100, Paint()..color = (1.0, 0.0, 0.0, 1.0));
    canvas.drawRect(50, 50, 150, 150, Paint()..color = (0.0, 1.0, 0.0, 1.0));
    canvas.restore();

    renderPass.end();
    commandBuffer.submit();
    onscreenTarget.dispose();

    requestAnimationFrame((double _) {
      render();
    }.toJS);
  }

  requestAnimationFrame((double _) {
    render();
  }.toJS);
}
