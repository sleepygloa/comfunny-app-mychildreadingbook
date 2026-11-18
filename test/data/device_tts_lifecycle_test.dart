import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/data/services/device_tts_service.dart';

class AvailableTts extends DeviceTtsService {
  @override
  Future<bool> isKoreanAvailable() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  for (final action in ['pause', 'stop', 'dispose']) {
    test('$action cancels speech waiting for engine initialization', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var speaks = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'setSpeechRate') {
              entered.complete();
              await release.future;
            }
            if (call.method == 'speak') speaks++;
            return 1;
          });
      final service = AvailableTts();
      final pending = service.speak('test');
      await entered.future;
      switch (action) {
        case 'pause':
          await service.pause();
        case 'stop':
          await service.stop();
        case 'dispose':
          await service.dispose();
      }
      release.complete();
      await pending;
      expect(speaks, 0);
      expect(service.isSpeaking, isFalse);
      await service.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }
}
