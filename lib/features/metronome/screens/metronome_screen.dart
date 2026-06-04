import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/audio/tone_generator.dart';
import '../../../main.dart';

import '../../../shared/widgets/toggle_button.dart';
import '../../../core/constants/app_constants.dart';

import '../../../core/utils/permissions_helper.dart';

/// Metronome UI and logic
class MetronomeScreen extends StatefulWidget {
  const MetronomeScreen({super.key});

  @override
  State<MetronomeScreen> createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends State<MetronomeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // --- STATE VARIABLES ---
  int _bpm = 120;
  bool _isPlaying = false;
  String _timeSignature = '4/4';
  int _currentBeat = 1;
  bool _isSwingingLeft = true;
  bool _soundEnabled = true;
  bool _flashEnabled = false;
  bool _isBeatFlashActive = false;

  // --- AUDIO TIMING UTILS ---
  Timer? _metronomeTimer;
  AudioSource? _strongSound;
  AudioSource? _weakSound;
  final List<DateTime> _tapTimes = [];
  static const int _maxTapDelayMs = 2000;

  // --- OPTICAL HARDWARE SYSTEM ---
  CameraController? _cameraController;
  bool _handsFreeCameraReady = false;
  bool _isCameraTransitioning = false;
  bool _isFlashing = false;
  int _lastFrameMs = 0;
  bool _lensWasCovered = false;
  bool _lensTriggerFired = false;
  Timer? _lensTriggerTimer;

  // --- NAVIGATION MANAGER ---
  TabController? _tabController;

  final List<String> _timeSignaturesList = [
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

  // --- LIFECYCLE METHODS ---
  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _tabController ??= DefaultTabController.maybeOf(context);
    _tabController?.addListener(_handleTabSelection);
  }

  /// Shuts down visual and audio states when navigating to the Tuner
  void _handleTabSelection() {
    if (_tabController != null && !_tabController!.indexIsChanging) {
      if (_tabController!.index == 0) {
        setState(() {
          if (_isPlaying) {
            _isPlaying = false;
            _metronomeTimer?.cancel();
          }

          _flashEnabled = false;
        });

        if (_handsFreeCameraReady) _stopHandsFreeCamera();
      }
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabSelection);
    _metronomeTimer?.cancel();
    _lensTriggerTimer?.cancel();
    _stopHandsFreeCamera();

    if (_strongSound != null) SoLoud.instance.disposeSource(_strongSound!);
    if (_weakSound != null) SoLoud.instance.disposeSource(_weakSound!);

    super.dispose();
  }

  // --- AUDIO GENERATION INITIALIZER ---

  /// Preloads "click's" into memory
  Future<void> _initAudio() async {
    final String strongPath = await ToneGenerator.generateClickFile(
      isStrongBeat: true,
    );
    final String weakPath = await ToneGenerator.generateClickFile(
      isStrongBeat: false,
    );

    _strongSound = await SoLoud.instance.loadFile(strongPath);
    _weakSound = await SoLoud.instance.loadFile(weakPath);
  }

  // --- HANDS-FREE HARDWARE MANAGER ---

  /// Toggles the hands-free mode; requests camera permissions
  void _onFlashToggled() async {
    if (_isCameraTransitioning) return;

    final bool newState = !_flashEnabled;

    if (newState) {
      _isCameraTransitioning = true;

      bool hasPermission = await PermissionsHelper.requestCameraPermission(
        context,
      );

      if (!mounted) {
        _isCameraTransitioning = false;
        return;
      }

      if (hasPermission) {
        setState(() => _flashEnabled = true);
        await _startHandsFreeCamera();

        if (mounted && _handsFreeCameraReady) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Hands-free mode enabled! Cover the camera to trigger.',
              ),
              backgroundColor: AppColors.primary,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
      _isCameraTransitioning = false;
    } else {
      _isCameraTransitioning = true;

      setState(() => _flashEnabled = false);
      await _stopHandsFreeCamera();

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }
      _isCameraTransitioning = false;
    }
  }

  /// Initializes the back camera
  Future<void> _startHandsFreeCamera() async {
    try {
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      _cameraController = controller;
      await controller.initialize();

      if (mounted && _flashEnabled) {
        setState(() => _handsFreeCameraReady = true);
        await controller.startImageStream(_onCameraFrame);
      } else {
        await controller.dispose();
        if (_cameraController == controller) _cameraController = null;
      }
    } catch (e) {
      debugPrint('Error starting camera safely: $e');
      if (mounted) {
        setState(() {
          _flashEnabled = false;
          _handsFreeCameraReady = false;
        });
      }
    }
  }

  /// Stops the camera stream
  Future<void> _stopHandsFreeCamera() async {
    while (_isFlashing) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    _lensTriggerTimer?.cancel();
    _lensTriggerTimer = null;
    _lensWasCovered = false;
    _lensTriggerFired = false;

    final controller = _cameraController;
    _cameraController = null;

    if (controller != null) {
      try {
        if (controller.value.isInitialized) {
          if (controller.value.isStreamingImages) {
            await controller.stopImageStream().catchError((_) {});
          }
          await controller.setFlashMode(FlashMode.off).catchError((_) {});
        }
        await controller.dispose();
      } catch (e) {
        debugPrint('Error disposing camera controller safely: $e');
      }
    }

    if (mounted) setState(() => _handsFreeCameraReady = false);
  }

  // --- COMPUTER VISION ALGORITHM ---

  /// Processes video frames to detect drops in brightness
  void _onCameraFrame(CameraImage image) {
    if (_isFlashing) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFrameMs < 100) return;
    _lastFrameMs = now;

    final plane = image.planes[0];
    final Uint8List bytes = plane.bytes;
    final int bytesPerRow = plane.bytesPerRow;
    final int width = image.width;
    final int height = image.height;

    int sum = 0;
    int count = 0;
    for (int row = 0; row < height; row += 8) {
      for (int col = 0; col < width; col += 8) {
        sum += bytes[row * bytesPerRow + col];
        count++;
      }
    }
    final double brightness = count > 0 ? sum / count : 255;
    final bool isDark = brightness < AppConstants.cameraDarkThreshold;

    if (isDark && !_lensTriggerFired) {
      if (!_lensWasCovered) {
        _lensWasCovered = true;

        _lensTriggerTimer?.cancel();
        _lensTriggerTimer = Timer(
          const Duration(milliseconds: AppConstants.lensTriggerDelayMs),
          () {
            if (_lensWasCovered && !_lensTriggerFired && mounted) {
              _lensTriggerFired = true;
              _togglePlay();
            }
          },
        );
      }
    } else if (!isDark) {
      _lensWasCovered = false;
      _lensTriggerTimer?.cancel();

      if (_lensTriggerFired) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _lensTriggerFired = false);
        });
      }
    }
  }

  /// Triggers a brief flashlight burst
  Future<void> _flashOnce() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        !_handsFreeCameraReady ||
        !_flashEnabled ||
        _isFlashing) {
      return;
    }

    setState(() => _isFlashing = true);

    try {
      if (controller.value.isInitialized) {
        await controller.setFlashMode(FlashMode.torch);
      }

      await Future.delayed(
        const Duration(milliseconds: AppConstants.flashDurationMs),
      );

      if (mounted && _flashEnabled && controller.value.isInitialized) {
        await controller.setFlashMode(FlashMode.off);
      }
    } catch (e) {
      debugPrint('Flash hardware exception intercepted safely: $e');
    } finally {
      await Future.delayed(
        const Duration(milliseconds: AppConstants.flashRecoveryDelayMs),
      );
      if (mounted) {
        setState(() => _isFlashing = false);
      }
    }
  }

  // --- METRONOME ENGINE & LOGIC ---

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _startMetronome(isInitialStart: true);
      } else {
        _metronomeTimer?.cancel();
      }
    });
  }

  /// Starts/restarts the timer controlling the metronome ticks
  void _startMetronome({bool isInitialStart = false}) {
    _metronomeTimer?.cancel();

    if (isInitialStart) {
      _currentBeat = 1;
      _isSwingingLeft = true;
      _playTick();
    }

    final int intervalMs = 60000 ~/ _bpm;
    _metronomeTimer = Timer.periodic(Duration(milliseconds: intervalMs), (
      timer,
    ) {
      _playTick();
    });
  }

  /// Fires audio and visual indicators for the current beat
  void _playTick() {
    final bool isLinear = _timeSignature == 'Linear';
    final int beatsPerMeasure = isLinear ? 4 : (int.tryParse(_timeSignature.split('/')[0]) ?? 4);

    if (_soundEnabled && _strongSound != null && _weakSound != null) {
      if (_currentBeat == 1 && !isLinear) {
        SoLoud.instance.play(_strongSound!);
      } else {
        SoLoud.instance.play(_weakSound!);
      }
    }

    setState(() {
      _isSwingingLeft = !_isSwingingLeft;
      
      _isBeatFlashActive = true;

      _currentBeat++;
      if (_currentBeat > beatsPerMeasure) {
        _currentBeat = 1;
      }
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() {
          _isBeatFlashActive = false;
        });
      }
    });

    if (_flashEnabled && _handsFreeCameraReady) {
      _flashOnce();
    }
  }

  void _updateBpm(int newBpm) {
    setState(() {
      _bpm = newBpm.clamp(AppConstants.minBpm, AppConstants.maxBpm);
      if (_isPlaying) {
        _startMetronome(isInitialStart: false);
      }
    });
  }

  // --- TAP TEMPO SYSTEM ---

  /// Calculates BPM based on the average time between consecutive taps
  void _handleTapTempo() {
    final now = DateTime.now();

    if (_tapTimes.isNotEmpty &&
        now.difference(_tapTimes.last).inMilliseconds > _maxTapDelayMs) {
      _tapTimes.clear();
    }

    _tapTimes.add(now);

    if (_tapTimes.length >= 2) {
      if (_tapTimes.length > 5) {
        _tapTimes.removeAt(0);
      }

      int totalIntervals = 0;
      for (int i = 1; i < _tapTimes.length; i++) {
        totalIntervals += _tapTimes[i]
            .difference(_tapTimes[i - 1])
            .inMilliseconds;
      }

      final int averageInterval = totalIntervals ~/ (_tapTimes.length - 1);

      if (averageInterval > 0) {
        int calculatedBpm = 60000 ~/ averageInterval;

        calculatedBpm = calculatedBpm.clamp(
          AppConstants.minBpm,
          AppConstants.maxBpm,
        );

        _updateBpm(calculatedBpm);
      }
    }
  }

  // --- UI PICKERS AND SHEETS ---

  /// Opens a bottom sheet menu to select the time signature
  void _showTimeSignaturePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,

      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (BuildContext context) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.only(
            top: 24.0,
            bottom: 40.0,
            left: 24.0,
            right: 24.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Time Signature',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 24),

              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: _timeSignaturesList.map((signature) {
                  final bool isSelected = signature == _timeSignature;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _timeSignature = signature;
                        if (_isPlaying) {
                          _startMetronome(isInitialStart: true);
                        }
                      });
                      Navigator.pop(context);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 75,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.inactive,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        signature,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                          color: isSelected ? Colors.white : AppColors.textDark,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- UI RENDER LAYOUT ---

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        const Spacer(flex: 2),

        // --- BPM COUNTER ---
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$_bpm',
              style: const TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'bpm',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),

        // --- BPM SLIDER ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: Colors.white,
              thumbColor: AppColors.primary,
              trackHeight: 8.0,
            ),
            child: Slider(
              value: _bpm.toDouble(),
              min: AppConstants.minBpm.toDouble(),
              max: AppConstants.maxBpm.toDouble(),
              onChanged: (newValue) {
                _updateBpm(newValue.toInt());
              },
            ),
          ),
        ),

        const Spacer(),

        // --- MANUAL TAP BUTTON ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Material(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(16),

            elevation: 12,

            shadowColor: Colors.black.withValues(alpha: 0.6),
            child: InkWell(
              onTap: _handleTapTempo,
              borderRadius: BorderRadius.circular(16),
              splashColor: Colors.white.withValues(alpha: 0.3),
              highlightColor: Colors.transparent,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: const Text(
                  'Tap',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
        ),

        const Spacer(),

        // --- VISUAL PENDULUM SWING ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Container(
            height: 40,
            width: double.infinity,
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.primary, width: 8),
                right: BorderSide(color: AppColors.primary, width: 8),
              ),
            ),
            child: AnimatedAlign(
              duration: Duration(milliseconds: 60000 ~/ _bpm),

              curve: Curves.linear,
              alignment: _isSwingingLeft
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: (_isBeatFlashActive && _currentBeat == 2 && _timeSignature != 'Linear')
                      ? AppColors.tertiary 
                      : AppColors.textDark,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),

        const Spacer(),

        // --- TIME SIGNATURE DISPLAY ---
        GestureDetector(
          onTap: _showTimeSignaturePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              _timeSignature,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
                color: AppColors.textDark,
              ),
            ),
          ),
        ),

        const Spacer(),

        // --- HARDWARE TOGGLE BUTTONS ---
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ToggleButton(
              icon: Icons.volume_up,
              isActive: _soundEnabled,
              onTap: () => setState(() => _soundEnabled = !_soundEnabled),
            ),
            const SizedBox(width: 24),

            Stack(
              clipBehavior: Clip.none,
              children: [
                ToggleButton(
                  icon: Icons.back_hand,
                  isActive: _flashEnabled,
                  onTap: _onFlashToggled,
                ),

                if (_handsFreeCameraReady)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: AppColors.secondary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.remove_red_eye,
                        size: 9,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),

        const Spacer(flex: 2),

        // --- PLAY / PAUSE CONTROLLER ---
        Container(
          margin: const EdgeInsets.only(left: 24, right: 24, bottom: 64),
          child: AnimatedPhysicalModel(
            duration: const Duration(milliseconds: 300),
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(30),
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: 0.6),

            color: _isPlaying ? AppColors.secondary : AppColors.textDark,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _togglePlay,
                borderRadius: BorderRadius.circular(30),
                splashColor: Colors.white.withValues(alpha: 0.3),
                highlightColor: Colors.transparent,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  alignment: Alignment.center,
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
