import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:camera/camera.dart';

import 'core/constants/app_colors.dart';
import 'features/tuner/screens/tuner_screen.dart';
import 'features/metronome/screens/metronome_screen.dart';

// --- GLOBAL VARIABLES ---
late List<CameraDescription> cameras;

// --- INITIALIZATION ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  cameras = await availableCameras();
  await SoLoud.instance.init();

  runApp(const TuneBeatApp());
}

// --- MAIN APP ---

/// Main application widget for TuneBeat
class TuneBeatApp extends StatelessWidget {
  const TuneBeatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TuneBeat',

      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Roboto',
      ),
      home: const MainScreen(),
    );
  }
}

/// Main application layout
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // --- TOP NAVIGATION BAR ---
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: const TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,

                    labelColor: AppColors.textDark,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),

                    unselectedLabelColor: AppColors.textLight,
                    unselectedLabelStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                    indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(
                        color: AppColors.primary,
                        width: 3,
                      ),

                      insets: EdgeInsets.symmetric(horizontal: 42),
                    ),
                    tabs: [
                      Tab(height: 56, text: 'Tuner'),
                      Tab(height: 56, text: 'Metronome'),
                    ],
                  ),
                ),
              ),

              // --- CORE TOOL VIEWPORTS ---
              const Expanded(
                child: TabBarView(children: [TunerScreen(), MetronomeScreen()]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
