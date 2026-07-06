import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/detection.dart';
import '../services/detector_service.dart';
import '../widgets/bounding_box_painter.dart';
import '../widgets/detection_hud.dart';

class DetectionPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const DetectionPage({super.key, required this.cameras});

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage>
    with WidgetsBindingObserver {
  // ── Camera ─────────────────────────────────────────────────────────────────
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _isCameraReady = false;
  bool _isFrontCamera = false;

  // ── Detector ───────────────────────────────────────────────────────────────
  final DetectorService _detector = DetectorService();
  bool _isDetecting = false;
  bool _detectionPaused = false;
  List<Detection> _detections = [];

  // ── Stats ──────────────────────────────────────────────────────────────────
  double _fps = 0.0;
  final _frameTimes = <DateTime>[];

  // ── Config ─────────────────────────────────────────────────────────────────
  double _confidenceThreshold = 0.20;
  bool _showControls = true;

  // ── Image size (after sensor rotation) ────────────────────────────────────
  Size _imageSize = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissionAndStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _detector.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startCamera(_cameraIndex);
    }
  }

  // ── Permission ─────────────────────────────────────────────────────────────
  Future<void> _requestPermissionAndStart() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      await _detector.initialize();
      await _startCamera(_cameraIndex);
    } else {
      if (mounted) {
        _showPermissionDenied();
      }
    }
  }

  void _showPermissionDenied() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Izin Kamera Diperlukan',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Aplikasi membutuhkan izin kamera untuk deteksi realtime.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => openAppSettings(),
            child: const Text('Buka Pengaturan',
                style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  // ── Camera ─────────────────────────────────────────────────────────────────
  Future<void> _startCamera(int index) async {
    if (widget.cameras.isEmpty) return;

    final camera = widget.cameras[index];
    _isFrontCamera =
        camera.lensDirection == CameraLensDirection.front;

    final prev = _controller;
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;

      // Determine image size considering sensor orientation
      final ori = camera.sensorOrientation;
      final w = _controller!.value.previewSize!.width;
      final h = _controller!.value.previewSize!.height;
      _imageSize = (ori == 90 || ori == 270) ? Size(h, w) : Size(w, h);

      await prev?.dispose();

      setState(() => _isCameraReady = true);
      _startImageStream();
    } catch (e) {
      debugPrint('[Camera] Init error: $e');
    }
  }

  void _startImageStream() {
    _controller?.startImageStream((CameraImage image) async {
      if (_isDetecting || _detectionPaused) return;
      _isDetecting = true;

      final t0 = DateTime.now();
      try {
        final results = await _detector.detect(
          image,
          confidenceThreshold: _confidenceThreshold,
          previewWidth:  _imageSize.width.toInt(),
          previewHeight: _imageSize.height.toInt(),
          sensorOrientation:
              widget.cameras[_cameraIndex].sensorOrientation,
          isFrontCamera: _isFrontCamera,
        );

        // FPS rolling window (last 10 frames)
        _frameTimes.add(DateTime.now());
        if (_frameTimes.length > 10) _frameTimes.removeAt(0);
        double fps = 0;
        if (_frameTimes.length >= 2) {
          final elapsed = _frameTimes.last
              .difference(_frameTimes.first)
              .inMilliseconds;
          fps = ((_frameTimes.length - 1) * 1000) / elapsed;
        }

        if (mounted) {
          setState(() {
            _detections = results;
            _fps = fps;
          });
        }
      } finally {
        _isDetecting = false;
      }
    });
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % widget.cameras.length;
    setState(() {
      _isCameraReady = false;
      _detections = [];
    });
    await _startCamera(_cameraIndex);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Camera preview ────────────────────────────────────────────
            _buildPreview(),

            // ── Bounding boxes ────────────────────────────────────────────
            if (_isCameraReady && _detections.isNotEmpty)
              CustomPaint(
                painter: BoundingBoxPainter(
                  detections: _detections,
                  previewSize: MediaQuery.of(context).size,
                  imageSize: _imageSize,
                ),
              ),

            // ── Top HUD (FPS + count) ─────────────────────────────────────
            Positioned(
              top: 12,
              left: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatsBar(fps: _fps, totalCount: _detections.length),
                  const SizedBox(height: 6),
                  DetectionCountBar(detections: _detections),
                ],
              ),
            ),

            // ── Title bar ─────────────────────────────────────────────────
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => setState(() => _showControls = !_showControls),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.tune, color: Colors.white, size: 20),
                ),
              ),
            ),

            // ── Bottom controls ───────────────────────────────────────────
            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildControls(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (!_isCameraReady) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.cyanAccent),
            SizedBox(height: 16),
            Text('Memuat kamera & model…',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _imageSize.width,
            height: _imageSize.height,
            child: CameraPreview(_controller!),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.90), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Confidence slider
          ConfidenceSlider(
            value: _confidenceThreshold,
            onChanged: (v) => setState(() => _confidenceThreshold = v),
          ),
          const SizedBox(height: 12),
          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pause / Resume
              _ControlButton(
                icon: _detectionPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                label: _detectionPaused ? 'Resume' : 'Pause',
                color: _detectionPaused
                    ? Colors.greenAccent
                    : Colors.orangeAccent,
                onTap: () =>
                    setState(() => _detectionPaused = !_detectionPaused),
              ),
              const SizedBox(width: 16),
              // Switch camera
              _ControlButton(
                icon: Icons.flip_camera_android_rounded,
                label: 'Ganti Kamera',
                color: Colors.cyanAccent,
                onTap: _switchCamera,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.8),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}
