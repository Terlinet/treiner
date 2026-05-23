import 'dart:js' as js;

// Usado apenas na web
void initMediaPipe(String? videoElementId) {
  js.context.callMethod('initMediaPipe', [videoElementId]);
}

void setPoseCallback(Function(String) callback) {
  js.context['onPoseDetected'] = (String landmarksJson) {
    callback(landmarksJson);
  };
}
