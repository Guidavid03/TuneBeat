import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:pitch_detector_dart/pitch_detector_result.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/audio/tone_generator.dart';
import '../widgets/gauge_painter.dart';
import '../widgets/note_button.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/permissions_helper.dart';

/// Tuner UI and pitch detection engine with reference tone generation.
class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  // --- REFERENCE CONFIGURATIONS ---

  String selectedFrequency = AppConstants.defaultTunerFrequency;
  String selectedTuning = AppConstants.defaultTuning;

  // --- DSP & PROCESSING CACHES ---
  final Map<String, double> _chromaticCache = {};
  final _audioRecorder = FlutterAudioCapture();
  late final PitchDetector _pitchDetector;
  bool _isListening = false;
  bool _isRequestingPermission = false;
  bool _permissionDenied = false;

  // --- UI NOTIFIERS ---
  final ValueNotifier<double> currentCents = ValueNotifier(0.0);
  final ValueNotifier<String> currentNote = ValueNotifier("--");
  final ValueNotifier<String> currentHzDisplay = ValueNotifier("--");

  // --- AUDIO OUTPUT MANIFEST ---
  int? activeNoteIndex;
  SoundHandle? _activeSoundHandle;
  final Map<String, AudioSource> _loadedSources = {};

  // --- NAVIGATION MANAGER ---
  TabController? _tabController;

  // --- LIFECYCLE METHODS ---
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pitchDetector = PitchDetector(
      audioSampleRate: AppConstants.audioSampleRate.toDouble(),
      bufferSize: AppConstants.pitchBufferSize,
    );

    _buildChromaticCache();
    WakelockPlus.enable();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await _preloadCurrentTuning();
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted && _tabController?.index == 0) {
          _startMicrophoneTest();
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tabController ??= DefaultTabController.maybeOf(context);
    _tabController?.addListener(_handleTabSelection);
  }

  void _handleTabSelection() {
    if (_tabController != null && !_tabController!.indexIsChanging) {
      if (_tabController!.index == 0) {
        if (!_isListening) _startMicrophoneTest();
      } else {
        _stopMicrophoneTest();

        _stopCurrentNote();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopMicrophoneTest();
      WakelockPlus.disable();
    } else if (state == AppLifecycleState.resumed) {
      if (_tabController?.index == 0) _startMicrophoneTest();
      WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController?.removeListener(_handleTabSelection);

    WakelockPlus.disable();
    _stopMicrophoneTest();

    currentCents.dispose();
    currentNote.dispose();
    currentHzDisplay.dispose();

    super.dispose();
  }

  // --- CHROMATIC MATHEMATICS ---

  /// Builds a map of expected frequencies for octaves 1 through 6 based on base A4 frequency
  void _buildChromaticCache() {
    _chromaticCache.clear();

    for (int i = 1; i <= 6; i++) {
      for (String n in AppConstants.chromaticScale) {
        String note = '$n$i';
        _chromaticCache[note] = _calculateTargetFrequency(note);
      }
    }
  }

  double _getBaseFrequency() {
    return double.tryParse(selectedFrequency.split(' ')[0]) ?? AppConstants.defaultBaseHz;
  }

  /// Calculates the mathematical frequency of a note using standard equal temperament
  double _calculateTargetFrequency(String noteWithOctave) {
    final double fBase = _getBaseFrequency();

    final Map<String, String> flatToSharp = {
      'Db': 'C#',
      'Eb': 'D#',
      'Gb': 'F#',
      'Ab': 'G#',
      'Bb': 'A#',
    };

    final match = RegExp(r'^([A-G][#b]?)([0-9])$').firstMatch(noteWithOctave);
    if (match == null) return 0.0;

    String note = match.group(1)!;
    int octave = int.parse(match.group(2)!);

    if (flatToSharp.containsKey(note)) {
      note = flatToSharp[note]!;
    }

    final int noteIndex = AppConstants.chromaticScale.indexOf(note);
    final int semitonesFromA4 = (noteIndex - 9) + ((octave - 4) * 12);

    return fBase * pow(2.0, semitonesFromA4 / 12.0);
  }

  List<double> _getCurrentActiveFrequencies() {
    final List<String> currentNotes = AppConstants.guitarTunings[selectedTuning]!;
    return currentNotes.map((note) => _calculateTargetFrequency(note)).toList();
  }

  // --- AUDIO CAPTURE AND DSP ENGINE ---

  /// Spawns the audio input thread stream and forwards buffers to the pitch analyzer
  Future<void> _startMicrophoneTest() async {
    if (_isRequestingPermission || _isListening || _permissionDenied) return;

    _isRequestingPermission = true;

    bool hasPermission = await PermissionsHelper.requestMicrophonePermission(
      context,
    );

    _isRequestingPermission = false;

    if (!hasPermission) {
      if (mounted) setState(() => _permissionDenied = true);
      return;
    }

    if (mounted && _permissionDenied) setState(() => _permissionDenied = false);

    await _audioRecorder.init();
    await _audioRecorder.start(
      _onAudioReceived,
      (error) => debugPrint('Microphone error: $error'),
      sampleRate: AppConstants.audioSampleRate,
      bufferSize: AppConstants.audioCaptureBufferSize,
    );

    setState(() => _isListening = true);
  }

  Future<void> _stopMicrophoneTest() async {
    await _audioRecorder.stop();
    if (mounted) {
      setState(() => _isListening = false);
    }
  }

  /// Core callback running autocorrelation to calculate frequency values and logarithmic cents difference
  void _onAudioReceived(dynamic audioChunk) async {
    if (!_isListening) return;

    List<double> audio = audioChunk.cast<double>();
    PitchDetectorResult result = await _pitchDetector.getPitchFromFloatBuffer(
      audio,
    );

    if (result.pitched &&
        result.probability > AppConstants.pitchProbabilityThreshold) {
      double detectedHz = result.pitch;

      String closestString = "";
      double targetHz = 0.0;
      double minCentsDifference = double.infinity;

      for (var entry in _chromaticCache.entries) {
        double expectedHz = entry.value;
        double centsDiff = (1200.0 * (log(detectedHz / expectedHz) / log(2)))
            .abs();

        if (centsDiff < minCentsDifference) {
          minCentsDifference = centsDiff;
          closestString = entry.key;
          targetHz = expectedHz;
        }
      }

      double finalCents = 1200.0 * (log(detectedHz / targetHz) / log(2));

      if (mounted && _isListening) {
        currentNote.value = closestString;
        currentCents.value = finalCents.clamp(-AppConstants.maxCentsDeviation, AppConstants.maxCentsDeviation);
        currentHzDisplay.value = "${detectedHz.toStringAsFixed(1)} Hz";
      }
    }
  }

  // --- REFERENCE TONE GENERATOR SYSTEM ---

  /// Preloads specific sine wave sound vectors into memory
  Future<void> _preloadCurrentTuning() async {
    final List<String> currentNotes = AppConstants.guitarTunings[selectedTuning]!;

    for (String note in currentNotes) {
      if (!_loadedSources.containsKey(note)) {
        double hz = _calculateTargetFrequency(note);
        if (hz > 0) {
          String path = await ToneGenerator.generateMicroLoop(hz);
          _loadedSources[note] = await SoLoud.instance.loadFile(path);
        }
      }
    }
  }

  Future<void> _unloadCurrentTuning() async {
    _stopCurrentNote();

    for (var source in _loadedSources.values) {
      SoLoud.instance.disposeSource(source);
    }

    _loadedSources.clear();
  }

  Future<void> _stopCurrentNote() async {
    if (_activeSoundHandle != null) {
      SoLoud.instance.stop(_activeSoundHandle!);
      _activeSoundHandle = null;
    }

    if (mounted) {
      setState(() {
        activeNoteIndex = null;
      });
    }
  }

  void _handleNoteTap(int index, String note) async {
    if (activeNoteIndex == index) {
      _stopCurrentNote();
      return;
    }

    _stopCurrentNote();

    setState(() {
      activeNoteIndex = index;
    });

    if (!_loadedSources.containsKey(note)) {
      final double hz = _calculateTargetFrequency(note);
      if (hz > 0) {
        String path = await ToneGenerator.generateMicroLoop(hz);
        _loadedSources[note] = await SoLoud.instance.loadFile(path);
      }
    }

    if (activeNoteIndex == index && _loadedSources.containsKey(note)) {
      _activeSoundHandle = SoLoud.instance.play(
        _loadedSources[note]!,
        looping: true,
      );
    }
  }

  // --- UI RENDER LAYOUT ---

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        const SizedBox(height: 12),

        // --- CALIBRATION DROP-DOWNS BAR ---
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: PopupMenuButton<String>(
                  clipBehavior: Clip.hardEdge,
                  surfaceTintColor: Colors.white,
                  initialValue: selectedFrequency,
                  offset: const Offset(0, 35),
                  constraints: const BoxConstraints(
                    minWidth: 140,
                    maxHeight: 225,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: Colors.white,
                  onSelected: (String newValue) async {
                    setState(() => selectedFrequency = newValue);
                    _buildChromaticCache();

                    await _unloadCurrentTuning();
                    await _preloadCurrentTuning();

                    ToneGenerator.clearTempFiles(
                      keepFrequencies: _getCurrentActiveFrequencies(),
                    );
                  },
                  itemBuilder: (context) => AppConstants.tunerFrequencies
                      .map(
                        (value) => PopupMenuItem(
                          value: value,
                          child: Text(
                            value,
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                      .toList(),

                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selectedFrequency,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_drop_down,
                          color: AppColors.textDark,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Container(
                width: 1,
                height: 20,
                color: Colors.grey.withValues(alpha: 0.3),
              ),

              Expanded(
                child: PopupMenuButton<String>(
                  clipBehavior: Clip.hardEdge,
                  surfaceTintColor: Colors.white,
                  initialValue: selectedTuning,
                  offset: const Offset(0, 35),
                  constraints: const BoxConstraints(
                    minWidth: 140,
                    maxHeight: 225,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: Colors.white,
                  onSelected: (String newValue) async {
                    setState(() => selectedTuning = newValue);

                    await _unloadCurrentTuning();
                    await _preloadCurrentTuning();

                    ToneGenerator.clearTempFiles(
                      keepFrequencies: _getCurrentActiveFrequencies(),
                    );
                  },
                  itemBuilder: (context) => AppConstants.guitarTunings.keys
                      .map(
                        (value) => PopupMenuItem(
                          value: value,
                          child: Text(
                            value,
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selectedTuning,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_drop_down,
                          color: AppColors.textDark,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const Spacer(flex: 2),

        // --- DYNAMIC TUNING READOUT HUD ---
        AnimatedBuilder(
          animation: Listenable.merge([
            currentCents,
            currentNote,
            currentHzDisplay,
          ]),
          builder: (context, child) {
            final double percentOutOfTune = (currentCents.value.abs() / AppConstants.maxCentsDeviation)
                .clamp(0.0, 1.0);
            final Color dynamicEdgeColor =
                Color.lerp(
                  AppColors.secondary,
                  AppColors.inactive,
                  percentOutOfTune,
                ) ??
                AppColors.secondary;

            return Column(
              children: [
                // Gauge Indicator
                SizedBox(
                  width: 260,
                  height: 130,

                  child: CustomPaint(
                    painter: GaugePainter(
                      cents: currentCents.value,
                      gaugeColor: dynamicEdgeColor,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Note Letter, Offset Error Value and Real-time Frequency Readouts
                Transform.translate(
                  offset: const Offset(0, -60),
                  child: Column(
                    children: [
                      Text(
                        currentNote.value,
                        style: const TextStyle(
                          fontSize: 90,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          height: 1.0,
                        ),
                      ),

                      Container(
                        width: 80,
                        height: 3,
                        color: AppColors.textDark,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                      ),

                      Text(
                        '${currentCents.value.toInt()} c',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),

                      Text(
                        currentHzDisplay.value,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),

        const Spacer(),

        // --- REFERENCE TONE BUTTONS DECK ---
        Container(
          margin: const EdgeInsets.only(left: 24, right: 24, bottom: 72),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),

          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Row(
              children: AppConstants.guitarTunings[selectedTuning]!.asMap().entries.map((entry) {
                final int index = entry.key;
                final String nota = entry.value;

                return Expanded(
                  child: NoteButton(
                    note: nota,
                    isActive: activeNoteIndex == index,

                    onTap: () => _handleNoteTap(index, nota),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
