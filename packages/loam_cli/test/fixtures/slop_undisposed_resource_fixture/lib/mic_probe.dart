// Condensed from WhisPaste's OnboardingMicProbe before commit 93adfb732: the
// level notifier was created here but dispose() never released it, while the
// timer and subscriptions were cancelled through a private teardown helper.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/framework.dart';

abstract class MicRecorder {
  Future<Stream<Uint8List>> startStream();
  Future<void> dispose();
}

class OnboardingMicProbe {
  OnboardingMicProbe({required MicRecorder recorder}) : _recorder = recorder;

  final MicRecorder _recorder;

  // Flagged: this is the leak fixed in 93adfb732.
  final ValueNotifier<double> _level = ValueNotifier<double>(0.0);

  StreamSubscription<Uint8List>? _pcmSub;
  Timer? _timeoutTimer;
  bool _disposed = false;

  Future<void> start() async {
    final pcmStream = await _recorder.startStream();
    _pcmSub = pcmStream.listen((_) => _level.value = 1.0);
    _timeoutTimer = Timer(const Duration(seconds: 5), () {});
  }

  Future<void> _teardownCapture() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _teardownCapture();
    await _recorder.dispose();
  }
}
