@staticInterop
import 'dart:js_interop';
import 'package:dart_web_gpu/canvas.dart';
import 'package:dart_web_gpu/types.dart';

import 'browser.dart';
import 'shaders.dart';
import 'wrapper.dart';

CanvasSwapchain? swapchain;
ContentContext? contentContext;
bool didInit = false;


Future<void> _ontimeSetup() async {
  if (didInit) {
    return;
  }
  var canvas = document.getElementById('canvas'.toJS) as HTMLCanvas;
  canvas.width = 1000.toJS;
  canvas.height = 800.toJS;
  final context = await Context.createContext();
  if (context == null) {
    return;
  }
  swapchain = await context.createSwapchain(canvas);
  contentContext = ContentContext(context, swapchain!.format);
  didInit = true;
}

void main(List<String> args) async {
  await _ontimeSetup();

  void render() {
    var onscreenTarget = swapchain!.createNext();
    var canvas = Canvas(contentContext!);

   // canvas.drawPaint(Paint()..color = (1.0, 0.5, 0.2, 1.0));
    canvas.saveLayer(Paint()..color = (0, 0, 0, 0.5));
    canvas.translate(100, 100);
    canvas.drawRect(
        Rect.fromLTRB(0, 0, 100, 100), Paint()..color = (1.0, 0.0, 0.0, 1.0));
    canvas.drawRect(
        Rect.fromLTRB(50, 50, 150, 150), Paint()..color = (0.0, 1.0, 0.0, 1.0));
    canvas.restore();
    canvas.drawCircle(
        Circle(Offset(200, 200), 400), Paint()..color = (0, 0, 1.0, 0.2));

    canvas.dispatch(onscreenTarget);

    onscreenTarget.dispose();

    requestAnimationFrame((double _) {
      render();
    }.toJS);
  }

  requestAnimationFrame((double _) {
    render();
  }.toJS);
}
