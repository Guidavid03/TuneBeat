import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';

/// Low-level binary writer generating loopable standard WAV files inside the OS cache
class ToneGenerator {
  // --- CACHE REGISTRY ---
  static final Map<double, String> _cache = {};

  // --- REFERENCE TONE LOOP GENERATION ---

  /// Synthesizes an multi-harmonic sine wave sample block for pitch referencing
  static Future<String> generateMicroLoop(double targetFrequency) async {
    if (_cache.containsKey(targetFrequency)) return _cache[targetFrequency]!;

    const int sampleRate = AppConstants.audioSampleRate;
    const int targetCycles = 15;

    final int numSamples = ((targetCycles * sampleRate) / targetFrequency)
        .round();
    final double adjustedFrequency = (targetCycles * sampleRate) / numSamples;

    const int numChannels = 1;
    const int bytesPerSample = 2;
    const int byteRate = sampleRate * numChannels * bytesPerSample;
    final int dataSize = numSamples * bytesPerSample;
    final int fileSize = 36 + dataSize;
    final bytes = BytesBuilder();

    // --- RIFF ENCODING HEADER DATA BLOCKS ---
    bytes.add(ascii.encode('RIFF'));
    bytes.add(_int32ToBytes(fileSize));
    bytes.add(ascii.encode('WAVE'));
    bytes.add(ascii.encode('fmt '));
    bytes.add(_int32ToBytes(16));
    bytes.add(_int16ToBytes(1));
    bytes.add(_int16ToBytes(numChannels));
    bytes.add(_int32ToBytes(sampleRate));
    bytes.add(_int32ToBytes(byteRate));
    bytes.add(_int16ToBytes(numChannels * bytesPerSample));
    bytes.add(_int16ToBytes(16));
    bytes.add(ascii.encode('data'));
    bytes.add(_int32ToBytes(dataSize));

    // --- HARMONIC ADDITIVE SYNTHESIS WAVEFORM LOOP ---
    const double totalWeight = 1.0 + 0.8 + 0.6 + 0.5 + 0.4 + 0.3;

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double fundamental = 1.00 * sin(2 * pi * adjustedFrequency * t);
      final double harmonic1 = 0.80 * sin(2 * pi * (adjustedFrequency * 2) * t);
      final double harmonic2 = 0.60 * sin(2 * pi * (adjustedFrequency * 3) * t);
      final double harmonic3 = 0.50 * sin(2 * pi * (adjustedFrequency * 4) * t);
      final double harmonic4 = 0.40 * sin(2 * pi * (adjustedFrequency * 5) * t);
      final double harmonic5 = 0.30 * sin(2 * pi * (adjustedFrequency * 6) * t);

      double value =
          (fundamental +
              harmonic1 +
              harmonic2 +
              harmonic3 +
              harmonic4 +
              harmonic5) /
          totalWeight;
      final int sample = (value * 32767 * 0.85).toInt();
      bytes.add(_int16ToBytes(sample));
    }

    // --- SYSTEM MEMORY PERSISTENCE FILE WRITER ---
    final Directory tempDir = await getTemporaryDirectory();
    final File file = File('${tempDir.path}/tone_$targetFrequency.wav');
    await file.writeAsBytes(bytes.toBytes());

    _cache[targetFrequency] = file.path;
    return file.path;
  }

  // --- CACHE FLUSHING MANAGEMENT ---

  /// Sweeps and deletes generated loop files to avoid filling device disk memory
  static void clearTempFiles({List<double> keepFrequencies = const []}) {
    final keysToRemove = <double>[];

    for (final entry in _cache.entries) {
      if (!keepFrequencies.contains(entry.key)) {
        final file = File(entry.value);
        if (file.existsSync()) {
          file.deleteSync();
        }
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _cache.remove(key);
    }
  }

  // --- METRONOME CLICK GENERATION SYSTEM ---
  /// Synthesizes a click sample accompanied by an exponential amplitude decay envelope
  static Future<String> generateClickFile({bool isStrongBeat = false}) async {
    final double frequency = isStrongBeat ? 1000.0 : 600.0;

    const double clickDuration = 0.05;
    const double totalDuration = 0.25;

    const int sampleRate = AppConstants.audioSampleRate;
    final int numSamples = (sampleRate * totalDuration).toInt();
    final int clickSamples = (sampleRate * clickDuration).toInt();

    const int numChannels = 1;
    const int bytesPerSample = 2;
    const int byteRate = sampleRate * numChannels * bytesPerSample;
    final int dataSize = numSamples * bytesPerSample;
    final int fileSize = 36 + dataSize;
    final bytes = BytesBuilder();

    // --- CLICK HEADER ENCODING ---
    bytes.add(ascii.encode('RIFF'));
    bytes.add(_int32ToBytes(fileSize));
    bytes.add(ascii.encode('WAVE'));
    bytes.add(ascii.encode('fmt '));
    bytes.add(_int32ToBytes(16));
    bytes.add(_int16ToBytes(1));
    bytes.add(_int16ToBytes(numChannels));
    bytes.add(_int32ToBytes(sampleRate));
    bytes.add(_int32ToBytes(byteRate));
    bytes.add(_int16ToBytes(numChannels * bytesPerSample));
    bytes.add(_int16ToBytes(16));
    bytes.add(ascii.encode('data'));
    bytes.add(_int32ToBytes(dataSize));

    // --- WAVE ENVELOPE SYNTH BLOCK ---
    for (int i = 0; i < numSamples; i++) {
      if (i < clickSamples) {
        final double t = i / sampleRate;
        final double envelope = 1.0 - (i / clickSamples);
        final double value = sin(2 * pi * frequency * t) * envelope;
        final int sample = (value * 32767).toInt();
        bytes.add(_int16ToBytes(sample));
      } else {
        bytes.add(_int16ToBytes(0));
      }
    }

    final Directory tempDir = await getTemporaryDirectory();

    final String fileName = isStrongBeat
        ? 'click_strong.wav'
        : 'click_weak.wav';
    final File file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes.toBytes());

    return file.path;
  }

  // --- BITWISE DATA TYPE CONVERTERS ---
  static Uint8List _int32ToBytes(int value) =>
      Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.little);
  static Uint8List _int16ToBytes(int value) =>
      Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.little);
}
