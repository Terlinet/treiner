import 'package:js/js.dart';

@JS('initMediaPipe')
external void initMediaPipe(dynamic videoElement);

@JS('onPoseDetected')
external set onPoseDetected(void Function(String results) f);
