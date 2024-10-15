@staticInterop
import 'dart:js_interop';
import 'package:dart_web_gpu/canvas.dart';
import 'package:dart_web_gpu/types.dart';

import 'browser.dart';
import 'shaders.dart';
import 'wrapper.dart';
import 'dart:math' as math;

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
    var rand = math.Random();
    const double size = 10;

    for (var x = 0.0; x < 1000; x += size) {
      for (var y = 0.0; y < 1000; y += size) {
        canvas.drawRect(
            Rect.fromLTRB(x, y, x + size, y + size),
            Paint()
              ..color =
                  (rand.nextDouble(), rand.nextDouble(), rand.nextDouble(), 1)
              ..mode = BlendMode.src);
      }
    }

    canvas.dispatch(onscreenTarget);
    onscreenTarget.dispose();

    requestAnimationFrame((double ts) {
      render();
    }.toJS);
  }

  requestAnimationFrame((double _) {
    render();
  }.toJS);
}
