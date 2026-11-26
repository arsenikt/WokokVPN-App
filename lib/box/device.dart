import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// The few things that need the operating system: reading aloud and text that
/// another app shared with us.
class Device {
  static const _channel = MethodChannel('com.wokok.box/device');
  static Process? _voice;

  static Future<bool> speak(String text) async {
    await stopSpeaking();
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        return await _channel.invokeMethod<bool>('speak', {'text': text}) ?? false;
      }
      if (Platform.isMacOS) {
        _voice = await Process.start('say', ['--', text]);
        return true;
      }
      if (Platform.isWindows) {
        // The text goes through stdin, never through the command line.
        const script = r'Add-Type -AssemblyName System.Speech;'
            r'[Console]::InputEncoding=[Text.Encoding]::UTF8;'
            r'$v=New-Object System.Speech.Synthesis.SpeechSynthesizer;'
            r"$ru=$v.GetInstalledVoices()|Where-Object{$_.VoiceInfo.Culture.Name -like 'ru*'}|Select-Object -First 1;"
            r'if($ru){$v.SelectVoice($ru.VoiceInfo.Name)};'
            r'$v.Speak([Console]::In.ReadToEnd())';
        final p = await Process.start(
            'powershell', ['-NoProfile', '-NonInteractive', '-Command', script]);
        p.stdin.add(utf8.encode(text));
        await p.stdin.close();
        _voice = p;
        return true;
      }
    } catch (_) {/* speech is optional */}
    return false;
  }

  static Future<void> stopSpeaking() async {
    _voice?.kill();
    _voice = null;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await _channel.invokeMethod<void>('stop');
      } catch (_) {}
    }
  }

  /// Text shared into the app (Android "Share" menu).
  static Future<void> listenShared(void Function(String text) onText) async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') onText(call.arguments as String);
    });
    try {
      final first = await _channel.invokeMethod<String>('sharedText');
      if (first != null && first.isNotEmpty) onText(first);
    } catch (_) {}
  }
}
