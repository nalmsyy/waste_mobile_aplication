import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/detection_page.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('[Main] Camera error: ${e.description}');
  }

  runApp(WasteDetectionApp(cameras: cameras));
}

class WasteDetectionApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const WasteDetectionApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deteksi Sampah – YOLO26m',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: SplashScreen(cameras: cameras),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00E5FF),
        secondary: Color(0xFF69F0AE),
        surface: Color(0xFF1A1A2E),
      ),
      scaffoldBackgroundColor: const Color(0xFF0D0D1A),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontFamily: 'Inter', color: Colors.white),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Color(0xFF00E5FF),
        thumbColor: Color(0xFF00E5FF),
      ),
    );
  }
}

/// Splash / landing screen shown briefly before the camera page.
class SplashScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const SplashScreen({super.key, required this.cameras});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fade  = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.6)));
    _scale = Tween<double>(begin: 0.85, end: 1).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();

    // Navigate to detection page after splash
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              DetectionPage(cameras: widget.cameras),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF69F0AE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withOpacity(0.40),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.recycling,
                        size: 54, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  // Title
                  const Text(
                    'Deteksi Sampah',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Subtitle
                  ShaderMask(
                    shaderCallback: (r) => const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF69F0AE)],
                    ).createShader(r),
                    child: const Text(
                      'YOLO26m · Eksperimen 4',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Classes
                  _ClassChips(),
                  const SizedBox(height: 40),
                  // Loading indicator
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Color(0xFF00E5FF),
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Memuat model…',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassChips extends StatelessWidget {
  final _classes = const [
    ('kertas', Color(0xFF4FC3F7)),
    ('logam', Color(0xFFFFB74D)),
    ('pakaian', Color(0xFFBA68C8)),
    ('plastik', Color(0xFF81C784)),
    ('tumbuhan', Color(0xFFA5D6A7)),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: _classes.map((e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: e.$2.withOpacity(0.15),
            border: Border.all(color: e.$2.withOpacity(0.6), width: 1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(e.$1,
              style: TextStyle(
                  color: e.$2,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        );
      }).toList(),
    );
  }
}
