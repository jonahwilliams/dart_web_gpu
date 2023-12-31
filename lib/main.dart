@staticInterop
import 'dart:js_interop';
import 'package:dart_web_gpu/canvas.dart';
import 'package:dart_web_gpu/types.dart';

import 'browser.dart';
import 'shaders.dart';
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
    var canvas = Canvas(contentContext);

    canvas.drawPaint(Paint()..color = (0.0, 1.0, 0.5, 1.0));
    canvas.saveLayer(Paint()..color = (0, 0, 0, 0.5));
    canvas.drawRect(
        Rect.fromLTRB(0, 0, 100, 100), Paint()..color = (1.0, 0.0, 0.0, 1.0));
    canvas.drawRect(
        Rect.fromLTRB(50, 50, 150, 150), Paint()..color = (0.0, 1.0, 0.0, 1.0));
    canvas.restore();

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
