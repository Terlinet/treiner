import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/js_bridge.dart' as bridge;
import 'welcome_screen.dart';
import 'dart:html' as html;

enum CameraStatus { loading, available, denied, error }

class BodyScanScreen extends StatefulWidget {
  final String modality;
  final String exercise;
  const BodyScanScreen({super.key, required this.modality, required this.exercise});

  @override
  State<BodyScanScreen> createState() => _BodyScanScreenState();
}

class _BodyScanScreenState extends State<BodyScanScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _textController = TextEditingController();
  CameraController? _cameraController;

  // Landmarks vindos do MediaPipe (via JS)
  List<dynamic> _landmarks = [];

  CameraStatus _cameraStatus = CameraStatus.loading;
  bool _isSynced = false;
  bool _isProcessing = false;
  String _iaStatus = "SISTEMA INICIANDO";
  int _reps = 0;

  // Lógica de contagem de agachamento
  bool _isSquatting = false;   // se está na posição de agachamento

  final String _apiBaseUrl = "https://tertulianoshow-terlinet-treiner.hf.space";

  @override
  void initState() {
    super.initState();
    _initCamera();
    _setupPoseCallback();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _audioPlayer.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _cameraStatus = CameraStatus.error);
      return;
    }
    final frontCamera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _cameraController = CameraController(frontCamera, ResolutionPreset.medium);
    await _cameraController!.initialize();
    if (mounted) {
      setState(() => _cameraStatus = CameraStatus.available);
    }
    // Aguarda um frame para obter o ID do vídeo (web)
    await Future.delayed(const Duration(milliseconds: 500));
    _startMediaPipe();
  }

  void _setupPoseCallback() {
    bridge.setPoseCallback((landmarksJson) {
      if (mounted && _isSynced) {
        final List<dynamic> newLandmarks = jsonDecode(landmarksJson);
        setState(() {
          _landmarks = newLandmarks;
        });
        _countSquat(newLandmarks);
      }
    });
  }

  void _startMediaPipe() {
    Future.delayed(const Duration(milliseconds: 300), () {
      try {
        final videoElement = html.document.querySelector('video');
        if (videoElement != null) {
          bridge.initMediaPipe(videoElement.id);
        } else {
          print("Elemento de vídeo não encontrado");
        }
      } catch (e) {
        print("Erro ao iniciar MediaPipe: $e");
      }
    });
  }

  void _countSquat(List<dynamic> landmarks) {
    if (landmarks.isEmpty || landmarks.length < 27) return;

    double leftHipY = landmarks[23]['y'];
    double rightHipY = landmarks[24]['y'];
    double hipY = (leftHipY + rightHipY) / 2;

    double leftKneeY = landmarks[25]['y'];
    double rightKneeY = landmarks[26]['y'];
    double kneeY = (leftKneeY + rightKneeY) / 2;

    bool currentlySquatting = kneeY > hipY + 0.1;

    if (currentlySquatting && !_isSquatting) {
      _isSquatting = true;
    } else if (!currentlySquatting && _isSquatting) {
      _isSquatting = false;
      setState(() {
        _reps++;
      });
      _speakToIA("$_reps", silent: true);
    }
  }

  Future<void> _speakToIA(String userText, {bool silent = false}) async {
    if (silent) {
      try {
        await http.post(
          Uri.parse('$_apiBaseUrl/query'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "text": userText,
            "modality": widget.exercise,
            "reps": _reps,
          }),
        );
      } catch (e) {}
      return;
    }

    setState(() {
      _isProcessing = true;
      _iaStatus = "TERLINET PENSANDO...";
    });
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/query'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "text": userText,
          "modality": widget.exercise,
          "reps": _reps,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _iaStatus = "TERLINET FALANDO");
        if (data['audio'] != null) {
          await _audioPlayer.play(BytesSource(base64Decode(data['audio'])));
        }
      }
    } catch (e) {
      setState(() => _iaStatus = "ERRO DE CONEXÃO");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _syncSystem() {
    setState(() {
      _isSynced = true;
      _iaStatus = "CAMERA ATIVA - POSICIONE-SE";
    });
    _speakToIA("INICIAR");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildCameraWithSkeleton(),
          if (!_isSynced) _buildSyncOverlay(),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatTile("EXERCÍCIO", widget.exercise),
                _buildStatTile("REPETIÇÕES", _reps.toString()),
              ],
            ),
          ),
          if (_isSynced) _buildInteractionPanel(),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraWithSkeleton() {
    if (_cameraStatus != CameraStatus.available || _cameraController == null) {
      return const Center(child: CircularProgressIndicator(color: WelcomeScreen.panoOrange));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_cameraController!),
        if (_landmarks.isNotEmpty)
          CustomPaint(
            painter: PosePainter(_landmarks),
            size: Size.infinite,
          ),
      ],
    );
  }

  Widget _buildSyncOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt, color: WelcomeScreen.panoOrange, size: 100),
            const SizedBox(height: 20),
            Text("TERLINET VISION", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("Sistema pronto para análise corporal", style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _syncSystem,
              style: ElevatedButton.styleFrom(
                backgroundColor: WelcomeScreen.panoOrange,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("INICIAR TREINO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractionPanel() {
    return Positioned(
      bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      left: 20,
      right: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              border: Border.all(color: WelcomeScreen.panoOrange.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(_iaStatus, style: GoogleFonts.orbitron(color: WelcomeScreen.panoOrange, fontSize: 10, fontWeight: FontWeight.bold)),
                if (_isProcessing) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(backgroundColor: Colors.black, color: WelcomeScreen.panoOrange)),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: WelcomeScreen.panoOrange.withOpacity(0.5)),
                  ),
                  child: TextField(
                    controller: _textController,
                    onSubmitted: (val) {
                      if (val.isNotEmpty) {
                        _speakToIA(val);
                        _textController.clear();
                      }
                    },
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: "Digite para falar com a TerlineT...",
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: Icon(_isProcessing ? Icons.sync : Icons.send, color: WelcomeScreen.panoOrange),
                onPressed: () {
                  if (_textController.text.isNotEmpty) {
                    _speakToIA(_textController.text);
                    _textController.clear();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.orbitron(color: WelcomeScreen.panoOrange, fontSize: 10)),
      Text(value, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
    ]);
  }
}

class PosePainter extends CustomPainter {
  final List<dynamic> landmarks;
  PosePainter(this.landmarks);

  static const List<List<int>> connections = [
    [11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
    [11, 23], [12, 24], [23, 24],
    [23, 25], [25, 27], [24, 26], [26, 28]
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) return;

    final paintLine = Paint()
      ..color = WelcomeScreen.panoOrange
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final paintPoint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (var conn in connections) {
      if (conn[0] < landmarks.length && conn[1] < landmarks.length) {
        final p1 = _getOffset(landmarks[conn[0]], size);
        final p2 = _getOffset(landmarks[conn[1]], size);
        if (p1 != null && p2 != null) {
          canvas.drawLine(p1, p2, paintLine);
        }
      }
    }

    for (var lm in landmarks) {
      final offset = _getOffset(lm, size);
      if (offset != null) {
        canvas.drawCircle(offset, 4, paintPoint);
      }
    }
  }

  Offset? _getOffset(dynamic lm, Size size) {
    if (lm == null) return null;
    final double x = (lm['x'] as num).toDouble() * size.width;
    final double y = (lm['y'] as num).toDouble() * size.height;
    if (lm['visibility'] != null && (lm['visibility'] as num) < 0.5) return null;
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(PosePainter oldDelegate) => true;
}
