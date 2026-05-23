import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import '../services/js_bridge.dart' as bridge;
import 'welcome_screen.dart';

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

  html.VideoElement? _videoElement;
  html.MediaStream? _mediaStream;
  List<dynamic> _landmarks = [];
  CameraStatus _cameraStatus = CameraStatus.loading;
  bool _isSynced = false;
  bool _isProcessing = false;
  String _iaStatus = "SISTEMA INICIANDO";
  int _reps = 0;

  bool _isSquatting = false;

  final String _apiBaseUrl = "https://tertulianoshow-terlinet-treiner.hf.space";

  @override
  void initState() {
    super.initState();
    _initCameraWeb();
    _setupPoseCallback();
  }

  @override
  void dispose() {
    _stopCamera();
    _audioPlayer.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _initCameraWeb() async {
    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        setState(() => _cameraStatus = CameraStatus.error);
        return;
      }
      final stream = await mediaDevices.getUserMedia({
        'video': {'facingMode': 'user'},
        'audio': false
      });
      _mediaStream = stream;
      _videoElement = html.VideoElement()
        ..id = 'pose-video'
        ..autoplay = true
        ..setAttribute('playsinline', 'true')
        ..style.position = 'absolute'
        ..style.top = '0'
        ..style.left = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.zIndex = '-1'; // Garante que o vídeo fique atrás do Flutter

      _videoElement!.srcObject = stream;
      await _videoElement!.play();

      html.document.body!.append(_videoElement!);

      if (mounted) {
        setState(() {
          _cameraStatus = CameraStatus.available;
          _iaStatus = "CÂMERA ATIVA - AGUARDANDO SINCRONIZAÇÃO";
        });
      }
      await Future.delayed(const Duration(milliseconds: 500));
      _startMediaPipe();
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraStatus = CameraStatus.error;
          _iaStatus = "ERRO: PERMISSÃO NEGADA";
        });
      }
    }
  }

  void _stopCamera() {
    _mediaStream?.getTracks().forEach((track) => track.stop());
    _videoElement?.remove();
    _videoElement = null;
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
    if (_videoElement != null) {
      bridge.initMediaPipe(_videoElement!.id);
    }
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
      setState(() => _reps++);
      _speakToIA("$_reps", silent: true);
    }
  }

  Future<void> _speakToIA(String userText, {bool silent = false}) async {
    if (silent) {
      try {
        await http.post(Uri.parse('$_apiBaseUrl/query'), headers: {"Content-Type": "application/json"}, body: jsonEncode({"text": userText, "modality": widget.exercise, "reps": _reps}));
      } catch (e) {}
      return;
    }

    setState(() { _isProcessing = true; _iaStatus = "TERLINET PENSANDO..."; });
    try {
      final response = await http.post(Uri.parse('$_apiBaseUrl/query'), headers: {"Content-Type": "application/json"}, body: jsonEncode({"text": userText, "modality": widget.exercise, "reps": _reps}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _iaStatus = "TERLINET FALANDO");
        if (data['audio'] != null) await _audioPlayer.play(BytesSource(base64Decode(data['audio'])));
      }
    } catch (e) {
      setState(() => _iaStatus = "ERRO DE CONEXÃO");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _syncSystem() {
    setState(() { _isSynced = true; _iaStatus = "CAMERA ATIVA - POSICIONE-SE"; });
    _speakToIA("INICIAR");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // TORNA O FLUTTER TRANSPARENTE
      body: Stack(
        children: [
          // Espaço do vídeo (está no fundo via DOM)
          if (_cameraStatus == CameraStatus.available) Container(color: Colors.transparent),

          // Desenho do esqueleto calibrado para o modo Cover do vídeo
          if (_landmarks.isNotEmpty && _isSynced)
            Positioned.fill(
              child: CustomPaint(
                painter: PosePainter(_landmarks, MediaQuery.of(context).size),
                size: MediaQuery.of(context).size,
              ),
            ),

          if (!_isSynced) _buildSyncOverlay(),

          // HUD Superior
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_buildStatTile("EXERCÍCIO", widget.exercise), _buildStatTile("REPETIÇÕES", _reps.toString())],
            ),
          ),

          if (_isSynced) _buildInteractionPanel(),

          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
          ),
        ],
      ),
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
              style: ElevatedButton.styleFrom(backgroundColor: WelcomeScreen.panoOrange, padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), border: Border.all(color: WelcomeScreen.panoOrange.withOpacity(0.3)), borderRadius: BorderRadius.circular(10)),
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
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(30), border: Border.all(color: WelcomeScreen.panoOrange.withOpacity(0.5))),
                  child: TextField(
                    controller: _textController,
                    onSubmitted: (val) { if (val.isNotEmpty) { _speakToIA(val); _textController.clear(); } },
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(hintText: "Digite para falar com a TerlineT...", hintStyle: TextStyle(color: Colors.white24, fontSize: 12), border: InputBorder.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(icon: Icon(_isProcessing ? Icons.sync : Icons.send, color: WelcomeScreen.panoOrange), onPressed: () { if (_textController.text.isNotEmpty) { _speakToIA(_textController.text); _textController.clear(); } }),
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
  final Size screenSize;
  PosePainter(this.landmarks, this.screenSize);

  static const List<List<int>> connections = [
    [11, 12], [11, 13], [13, 15], [12, 14], [14, 16],
    [11, 23], [12, 24], [23, 24],
    [23, 25], [25, 27], [24, 26], [26, 28]
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) return;

    final paintLine = Paint()..color = WelcomeScreen.panoOrange..strokeWidth = 4.0..style = PaintingStyle.stroke;
    final paintPoint = Paint()..color = Colors.white..style = PaintingStyle.fill;

    // MATEMÁTICA DE MAPEAMENTO (Ajustado para o modo Cover)
    const double videoAspect = 4 / 3; // Padrão MediaPipe
    final double screenAspect = screenSize.width / screenSize.height;

    double scale;
    double offsetX = 0;
    double offsetY = 0;

    if (screenAspect < videoAspect) {
      scale = screenSize.height;
      offsetX = (screenSize.height * videoAspect - screenSize.width) / 2;
    } else {
      scale = screenSize.width / videoAspect;
      offsetY = (screenSize.width / videoAspect - screenSize.height) / 2;
    }

    Offset getOffset(dynamic lm) {
      // Inverte X para efeito espelho e aplica escala do modo cover
      double x = (1.0 - (lm['x'] as num).toDouble()) * (scale * videoAspect) - offsetX;
      double y = (lm['y'] as num).toDouble() * scale - offsetY;
      return Offset(x, y);
    }

    for (var conn in connections) {
      if (conn[0] < landmarks.length && conn[1] < landmarks.length) {
        final p1 = getOffset(landmarks[conn[0]]);
        final p2 = getOffset(landmarks[conn[1]]);
        canvas.drawLine(p1, p2, paintLine);
      }
    }

    for (var lm in landmarks) {
      if (lm['visibility'] > 0.5) {
        canvas.drawCircle(getOffset(lm), 4, paintPoint);
      }
    }
  }

  @override
  bool shouldRepaint(PosePainter oldDelegate) => true;
}
