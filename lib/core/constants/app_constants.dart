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
  static const int defaultBpm = 120;
  static const String defaultTimeSignature = '4/4';

    // --- TUNER DEFAULTS AND LIMITS ---
  static const String defaultTunerFrequency = '440 Hz';
  static const String defaultTuning = 'E Standard';
  static const double defaultBaseHz = 440.0;
  
  static const double maxCentsDeviation = 50.0;
  static const int tunerMicrophoneInitDelayMs = 100;

  // --- TAP TEMPO SYSTEM ---
  static const int maxTapDelayMs = 2000;
  static const int maxTapTempoHistory = 5;

  // --- HARDWARE CALIBRATIONS ---
  static const double cameraDarkThreshold = 20.0;
  static const int lensTriggerDelayMs = 350;
  static const int lensTriggerResetDelayMs = 500;
  static const int cameraFrameThrottleMs = 100;
  static const int maxFlashBpm = 140;

  // --- UI TIMINGS ---
  static const int visualFlashDurationMs = 150;

  // --- MUSIC THEORY AND DOMAIN ---
  static const List<String> tunerFrequencies = [
    '415 Hz', '430 Hz', '432 Hz', '438 Hz', 
    '440 Hz', '442 Hz', '444 Hz', '446 Hz',
  ];

  static const List<String> chromaticScale = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 
    'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  static const Map<String, List<String>> guitarTunings = {
    'E Standard': ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'],
    'Eb Standard': ['Eb2', 'Ab2', 'Db3', 'Gb3', 'Bb3', 'Eb4'],
    'D Standard': ['D2', 'G2', 'C3', 'F3', 'A3', 'D4'],
    'C Standard': ['C2', 'F2', 'Bb2', 'Eb3', 'G3', 'C4'],
    'Drop D': ['D2', 'A2', 'D3', 'G3', 'B3', 'E4'],
    'Drop C#': ['C#2', 'G#2', 'C#3', 'F#3', 'A#3', 'D#4'],
    'Drop C': ['C2', 'G2', 'C3', 'F3', 'A3', 'D4'],
    'Drop B': ['B1', 'F#2', 'B2', 'E3', 'G#3', 'C#4'],
    'Drop A': ['A1', 'E2', 'A2', 'D3', 'F#3', 'B3'],
    'Open G': ['D2', 'G2', 'D3', 'G3', 'B3', 'D4'],
    'Open D': ['D2', 'A2', 'D3', 'F#3', 'A3', 'D4'],
    'Open E': ['E2', 'B2', 'E3', 'G#3', 'B3', 'E4'],
  };

  static const List<String> timeSignatures = [
    'Linear',
    '2/4',
    '3/4',
    '4/4',
    '5/4',
    '6/8',
    '7/8',
    '9/8',
    '12/8',
  ];
}
