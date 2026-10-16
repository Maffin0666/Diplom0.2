import 'package:flutter/material.dart';

/// Preferences are stored with the existing settings; old installations keep defaults.
class AppPreferences {
  const AppPreferences({
    this.highContrast = false,
    this.boldText = false,
    this.reduceMotion = false,
    this.spokenHints = true,
    this.haptics = true,
    this.earcons = true,
    this.cameraGuidance = true,
    this.continuousVoice = false,
    this.voiceMode = 'auto',
    this.commandSeconds = 5,
    this.playbackSpeed = 1,
    this.autoPlay = false,
    this.showMascot = true,
    this.showVoiceDock = true,
    this.autoCapture = false,
    this.readingGuide = false,
    this.palette = 'standard',
    this.fontMode = 'system',
    this.letterSpacing = 0,
    this.lineHeight = 1.4,
  });
  final bool highContrast,
      boldText,
      reduceMotion,
      spokenHints,
      haptics,
      earcons;
  final bool cameraGuidance, continuousVoice, autoPlay;
  final bool showMascot, showVoiceDock, autoCapture, readingGuide;
  final String palette;
  final String fontMode;
  final double letterSpacing, lineHeight;
  final String voiceMode;
  final int commandSeconds;
  final double playbackSpeed;

  factory AppPreferences.fromJson(Map<String, dynamic> json) => AppPreferences(
        highContrast: json['high_contrast'] == true,
        boldText: json['bold_text'] == true,
        reduceMotion: json['reduce_motion'] == true,
        spokenHints: json['spoken_hints'] != false,
        haptics: json['haptics'] != false,
        earcons: json['earcons'] != false,
        cameraGuidance: json['camera_guidance'] != false,
        continuousVoice: json['continuous_voice'] == true,
        autoPlay: json['auto_play'] == true,
        showMascot: json['show_mascot'] != false,
        showVoiceDock: json['show_voice_dock'] != false,
        autoCapture: json['auto_capture'] == true,
        readingGuide: json['reading_guide'] == true,
        palette: const [
          'standard',
          'black_yellow',
          'inverse',
          'monochrome',
          'protanopia',
          'deuteranopia',
          'tritanopia'
        ].contains(json['palette'])
            ? json['palette'] as String
            : 'standard',
        fontMode: const ['system', 'open_dyslexic', 'atkinson']
                .contains(json['font_mode'])
            ? json['font_mode'] as String
            : 'system',
        letterSpacing:
            ((json['letter_spacing'] as num?)?.toDouble() ?? 0).clamp(0, 3),
        lineHeight:
            ((json['line_height'] as num?)?.toDouble() ?? 1.4).clamp(1.2, 2),
        voiceMode: ['auto', 'android', 'server'].contains(json['voice_mode'])
            ? json['voice_mode'] as String
            : 'auto',
        commandSeconds:
            ((json['command_seconds'] as num?)?.toInt() ?? 5).clamp(3, 8),
        playbackSpeed:
            ((json['playback_speed'] as num?)?.toDouble() ?? 1).clamp(.75, 3),
      );

  Map<String, dynamic> toJson() => {
        'high_contrast': highContrast,
        'bold_text': boldText,
        'reduce_motion': reduceMotion,
        'spoken_hints': spokenHints,
        'haptics': haptics,
        'earcons': earcons,
        'camera_guidance': cameraGuidance,
        'continuous_voice': continuousVoice,
        'voice_mode': voiceMode,
        'command_seconds': commandSeconds,
        'playback_speed': playbackSpeed,
        'auto_play': autoPlay,
        'show_mascot': showMascot,
        'show_voice_dock': showVoiceDock,
        'auto_capture': autoCapture,
        'reading_guide': readingGuide,
        'palette': palette,
        'font_mode': fontMode,
        'letter_spacing': letterSpacing,
        'line_height': lineHeight,
      };
}

class PreferencesScope extends InheritedWidget {
  const PreferencesScope(
      {super.key, required this.preferences, required super.child});
  final AppPreferences preferences;
  static AppPreferences of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PreferencesScope>()
          ?.preferences ??
      const AppPreferences();
  @override
  bool updateShouldNotify(PreferencesScope oldWidget) =>
      preferences != oldWidget.preferences;
}
