import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Explicit vibration uses Android's vibrator rather than the touch-feedback
/// setting. The returned value only confirms that Android accepted the request.
abstract final class AppHaptics {
  static const _channel = MethodChannel('lektoria/haptics');

  static Future<bool> tone(String kind) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      await SystemSound.play(SystemSoundType.click);
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('tone', {'kind': kind}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> vibrate(
      {bool test = false, String kind = 'confirm'}) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      await HapticFeedback.mediumImpact();
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>(
            'vibrate',
            {'durationMs': test ? 180 : 55, 'kind': kind},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
