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
          clearColor: (0.0, 0.0, 0.0, 0.0),
          loadOp: LoadOP.clear,
          storeOp: StoreOp.store,
          renderTarget: onscreenTarget,
        )
      ],
    );
    var canvas = Canvas(contentContext, renderPass, 800, 800);

    canvas.drawRect(0, 0, 20, 20, (1.0, 0.0, 0.0, 1.0));
    canvas.drawRect(10, 10, 40, 40, (0.0, 1.0, 0.0, 1.0));
    canvas.drawRect(100, 100, 200, 200, (0.0, 1.0, 1.0, 1.0));
    canvas.translate(40, 40);
    canvas.drawCircle(20, 20, 40, (1.0, 0.0, 0.0, 1.0));

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
