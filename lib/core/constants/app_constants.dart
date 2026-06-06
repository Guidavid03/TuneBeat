/// Configuration values (avoiding magic numbers)
class AppConstants {

  // --- AUDIO AND TUNER SPECIFICATIONS ---
  static const int audioSampleRate = 44100;
  static const int pitchBufferSize = 2000;
  static const int audioCaptureBufferSize = 3000;
  static const double pitchProbabilityThreshold = 0.8;

  // --- METRONOME BOUNDARIES ---
  static const int minBpm = 40;
  static const int maxBpm = 220;

  // --- HARDWARE CALIBRATIONS ---
  static const double cameraDarkThreshold = 20.0;
  static const int lensTriggerDelayMs = 350;
}
