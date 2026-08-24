import 'dart:async';

class RateLimiter {
  /// Maximum allowed bytes per second.
  /// If 0 or negative, rate limiting is disabled.
  final int maxBytesPerSecond;

  int _bytesSent = 0;
  final Stopwatch _stopwatch = Stopwatch();

  RateLimiter(this.maxBytesPerSecond) {
    if (maxBytesPerSecond > 0) {
      _stopwatch.start();
    }
  }

  /// Throttle execution to ensure bytes sent over time does not exceed [maxBytesPerSecond].
  /// Call this after pushing a chunk of [newBytes] to the socket.
  Future<void> throttle(int newBytes) async {
    if (maxBytesPerSecond <= 0) return;

    _bytesSent += newBytes;

    // Calculate how many milliseconds it SHOULD take to send _bytesSent at max speed.
    final targetMs = (_bytesSent / maxBytesPerSecond * 1000).toInt();
    final elapsedMs = _stopwatch.elapsedMilliseconds;

    // If we've sent data faster than the target time, pause for the difference.
    if (elapsedMs < targetMs) {
      final delayMs = targetMs - elapsedMs;
      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    // Periodically reset the stopwatch and bytes to prevent overflow
    // and to allow catching up if we briefly dropped below max speed.
    if (_stopwatch.elapsedMilliseconds > 5000) {
      _stopwatch.start(); // ensure running
      _stopwatch.reset();
      _bytesSent = 0;
    }
  }
}
