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

    var builder = PathBuilder()
      ..moveTo(Offset(10, 10))
      ..lineTo(Offset(20, 10))
      ..lineTo(Offset(30, 20))
      ..lineTo(Offset(40, 10))
      ..quadraticBezierTo(Offset(0, 0), Offset(20, -10))
      ..close();
    var path = builder.takePath();

    canvas.translate(400, 400);
    canvas.drawPath(path, Paint()..color = (1.0, 0.0, 0.0, 1.0));

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
