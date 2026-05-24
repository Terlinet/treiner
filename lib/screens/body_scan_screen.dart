import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import '../services/js_bridge.dart' as bridge;
import 'welcome_screen.dart';

import 'package:flutter_tts/flutter_tts.dart';

enum CameraStatus { loading, available, denied, error }

class BodyScanScreen extends StatefulWidget {
  final String modality;
  final String exercise;
  const BodyScanScreen({super.key, required this.modality, required this.exercise});

  @override
  State<BodyScanScreen> createState() => _BodyScanScreenState();
}

class _BodyScanScreenState extends State<BodyScanScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  final TextEditingController _textController = TextEditingController();

  html.VideoElement? _videoElement;
  html.MediaStream? _mediaStream;
  List<dynamic> _landmarks = [];
  CameraStatus _cameraStatus = CameraStatus.loading;
  bool _isSynced = false;
  bool _isProcessing = false;
  String _iaStatus = "SISTEMA INICIANDO";
  int _reps = 0;
  bool _isInMovement = false;

  String? _selectedGoal;
  int? _targetReps;
  int _currentSet = 1;
  final int _totalSets = 3;
  bool _goalReached = false;
  bool _isResting = false;
  int _restSeconds = 45;
  Timer? _restTimer;

  final String _apiBaseUrl = "https://tertulianoshow-terlinet-treiner.hf.space";

  @override
  void initState() {
    super.initState();
    _initTts();
    _initCameraWeb();
    _setupPoseCallback();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("pt-BR");
    await _flutterTts.setSpeechRate(1.0); // Velocidade normal/rápida para soar natural
    await _flutterTts.setPitch(1.0);
  }

  @override
  void dispose() {
    _stopCamera();
    _flutterTts.stop();
    _textController.dispose();
    _restTimer?.cancel();
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
        ..style.objectFit = 'cover';

      html.document.body?.append(_videoElement!);
      _startMediaPipe();

      if (mounted) {
        setState(() => _cameraStatus = CameraStatus.available);
      }
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
        _processExercise(newLandmarks);
      }
    });
  }

  void _startMediaPipe() {
    if (_videoElement != null) {
      bridge.initMediaPipe(_videoElement!.id);
    }
  }

  void _processExercise(List<dynamic> landmarks) {
    if (landmarks.isEmpty) return;

    switch (widget.exercise.toUpperCase()) {
      case 'AGACHAMENTO':
        _countSquat(landmarks);
        break;
      case 'ROSCA DIRETA':
        _countBicepCurl(landmarks);
        break;
      case 'ELEVAÇÃO LATERAL':
        _countLateralRaise(landmarks);
        break;
      case 'CAMINHADA ESTACIONÁRIA':
      case 'CORRIDA ESTACIONÁRIA':
        _countStationaryWalk(landmarks);
        break;
      default:
        break;
    }
  }

  void _countStationaryWalk(List<dynamic> landmarks) {
    if (landmarks.length < 29) return;

    // Verificar visibilidade (quadril e joelhos)
    final criticalPoints = [23, 24, 25, 26];
    for (var i in criticalPoints) {
      if (landmarks[i]['visibility'] < 0.5) return;
    }

    // Lógica: Se o joelho subir acima de uma linha imaginária próxima ao quadril
    // Usamos a diferença de Y (Y aumenta para baixo)
    double leftHipY = landmarks[23]['y'];
    double rightHipY = landmarks[24]['y'];
    double avgHipY = (leftHipY + rightHipY) / 2;

    double leftKneeY = landmarks[25]['y'];
    double rightKneeY = landmarks[26]['y'];

    // Sensibilidade: Caminhada (0.05) vs Corrida (0.0 - Joelho no nível do quadril)
    double threshold = widget.exercise == 'CORRIDA ESTACIONÁRIA' ? 0.0 : 0.05;
    bool kneeRaised = leftKneeY < (avgHipY + threshold) || rightKneeY < (avgHipY + threshold);

    if (kneeRaised && !_isInMovement && !_goalReached) {
      _isInMovement = true;
    } else if (!kneeRaised && _isInMovement) {
      _isInMovement = false;
      setState(() => _reps++);
      _checkGoal();
      _flutterTts.speak("$_reps");
      _speakToIA("$_reps", isBackground: true);
    }
  }

  double _calculateAngle(dynamic a, dynamic b, dynamic c) {
    double radians = math.atan2(c['y'] - b['y'], c['x'] - b['x']) -
                     math.atan2(a['y'] - b['y'], a['x'] - b['x']);
    double angle = (radians * 180.0 / math.pi).abs();
    if (angle > 180.0) angle = 360.0 - angle;
    return angle;
  }

  void _countSquat(List<dynamic> landmarks) {
    if (landmarks.length < 29) return;

    final criticalPoints = [23, 24, 25, 26, 27, 28];
    for (var i in criticalPoints) {
      if (landmarks[i]['visibility'] < 0.5) return;
    }

    double leftAngle = _calculateAngle(landmarks[23], landmarks[25], landmarks[27]);
    double rightAngle = _calculateAngle(landmarks[24], landmarks[26], landmarks[28]);
    double avgAngle = (leftAngle + rightAngle) / 2;

    if (avgAngle < 110 && !_isInMovement && !_goalReached) {
      _isInMovement = true;
    } else if (avgAngle > 155 && _isInMovement) {
      _isInMovement = false;
      setState(() => _reps++);
      _checkGoal();
      _flutterTts.speak("$_reps");
      _speakToIA("$_reps", isBackground: true);
    }
  }

  void _countBicepCurl(List<dynamic> landmarks) {
    if (landmarks.length < 17) return;

    final criticalPoints = [11, 13, 15, 12, 14, 16];
    for (var i in criticalPoints) {
      if (landmarks[i]['visibility'] < 0.5) return;
    }

    double leftAngle = _calculateAngle(landmarks[11], landmarks[13], landmarks[15]);
    double rightAngle = _calculateAngle(landmarks[12], landmarks[14], landmarks[16]);
    double avgAngle = (leftAngle + rightAngle) / 2;

    if (avgAngle < 40 && !_isInMovement && !_goalReached) {
      _isInMovement = true;
    } else if (avgAngle > 150 && _isInMovement) {
      _isInMovement = false;
      setState(() => _reps++);
      _checkGoal();
      _flutterTts.speak("$_reps");
      _speakToIA("$_reps", isBackground: true);
    }
  }

  void _countLateralRaise(List<dynamic> landmarks) {
    if (landmarks.length < 15) return;

    final criticalPoints = [11, 13, 12, 14, 23, 24];
    for (var i in criticalPoints) {
      if (landmarks[i]['visibility'] < 0.5) return;
    }

    double leftAngle = _calculateAngle(landmarks[23], landmarks[11], landmarks[13]);
    double rightAngle = _calculateAngle(landmarks[24], landmarks[12], landmarks[14]);
    double avgAngle = (leftAngle + rightAngle) / 2;

    if (avgAngle > 80 && !_isInMovement && !_goalReached) {
      _isInMovement = true;
    } else if (avgAngle < 30 && _isInMovement) {
      _isInMovement = false;
      setState(() => _reps++);
      _checkGoal();
      _flutterTts.speak("$_reps");
      _speakToIA("$_reps", isBackground: true);
    }
  }

  void _checkGoal() {
    if (_targetReps != null && _reps >= _targetReps! && !_goalReached) {
      _goalReached = true;
      _flutterTts.stop();

      if (_currentSet < _totalSets) {
        _startRestPeriod();
      } else {
        _speakToIA("OBJETIVO_ALCANCADO");
      }
    }
  }

  void _startRestPeriod() {
    setState(() {
      _isResting = true;
      _restSeconds = 45;
      _iaStatus = "INTERVALO DE RECUPERAÇÃO";
    });

    _flutterTts.speak("Série concluída! Hora de descansar. Você tem 45 segundos.");

    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_restSeconds > 0) {
        setState(() => _restSeconds--);
        if (_restSeconds == 10) _flutterTts.speak("10 segundos para começar.");
      } else {
        timer.cancel();
        _nextSet();
      }
    });
  }

  void _nextSet() {
    setState(() {
      _currentSet++;
      _reps = 0;
      _isResting = false;
      _goalReached = false;
      _iaStatus = "SÉRIE $_currentSet INICIADA";
    });
    _flutterTts.speak("Descanso encerrado! Vamos para a série $_currentSet. Posicione-se e pode começar!");
    _speakToIA("INICIAR_PROXIMA_SERIE", isBackground: true);
  }

  void _selectGoal(String goal) {
    setState(() {
      _selectedGoal = goal;
      bool isWalk = widget.exercise == 'CAMINHADA ESTACIONÁRIA';
      bool isRun = widget.exercise == 'CORRIDA ESTACIONÁRIA';

      if (goal == "Emagrecer") {
        _targetReps = isRun ? 300 : (isWalk ? 100 : 15);
      } else if (goal == "Ganhar Massa") {
        _targetReps = isRun ? 150 : (isWalk ? 50 : 10);
      } else if (goal == "Resistência") {
        _targetReps = isRun ? 500 : (isWalk ? 200 : 20);
      }
    });

    _flutterTts.stop();
    _flutterTts.speak("Objetivo $goal.");
    String unit = (widget.exercise.contains("CAMINHADA") || widget.exercise.contains("CORRIDA")) ? "passos" : "repetições";
    _flutterTts.speak("A meta são $_totalSets séries de $_targetReps $unit.");
    _flutterTts.speak("O tempo de pausa entre as séries deve ficar entre 45 segundos e 2 minutos, dependendo do seu objetivo e do nível de cansaço.");
    _flutterTts.speak("Pode começar a primeira série!");
  }

  void _playBase64Audio(String base64String) {
    try {
      final blob = html.Blob([base64Decode(base64String)], 'audio/mpeg');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final audio = html.AudioElement(url);
      audio.play();
    } catch (e) {
      print("Erro ao tocar áudio: $e");
    }
  }

  Future<void> _speakToIA(String userText, {bool silent = false, bool isBackground = false}) async {
    if (silent) {
      try {
        await http.post(Uri.parse('$_apiBaseUrl/query'), headers: {"Content-Type": "application/json"}, body: jsonEncode({"text": userText, "modality": widget.exercise, "reps": _reps}));
      } catch (e) {}
      return;
    }

    if (!isBackground) {
      setState(() { _isProcessing = true; _iaStatus = "TERLINET PENSANDO..."; });
    }

    try {
      final response = await http.post(Uri.parse('$_apiBaseUrl/query'), headers: {"Content-Type": "application/json"}, body: jsonEncode({"text": userText, "modality": widget.exercise, "reps": _reps}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String textToSpeak = data['text'] ?? "";
        String? audioBase64 = data['audio'];

        if (textToSpeak.isNotEmpty && !isBackground) {
          setState(() => _iaStatus = "TERLINET FALANDO");
        }

        if (audioBase64 != null) {
          _playBase64Audio(audioBase64);
        } else if (textToSpeak.isNotEmpty) {
          await _flutterTts.speak(textToSpeak);
        }
      }
    } catch (e) {
      if (!isBackground) setState(() => _iaStatus = "ERRO DE CONEXÃO");
    } finally {
      if (!isBackground) setState(() => _isProcessing = false);
    }
  }

  void _syncSystem() {
    setState(() { _isSynced = true; _iaStatus = "SELECIONE SEU OBJETIVO"; });
    _flutterTts.stop();
    _flutterTts.speak("Olá! Escolha seu objetivo abaixo: Emagrecer, Ganhar Massa ou Resistência.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          if (_cameraStatus == CameraStatus.available) Container(color: Colors.transparent),

          if (_landmarks.isNotEmpty && _isSynced)
            Positioned.fill(
              child: CustomPaint(
                painter: PosePainter(_landmarks, MediaQuery.of(context).size),
                size: MediaQuery.of(context).size,
              ),
            ),

          if (!_isSynced) _buildSyncOverlay(),

          if (_isSynced && _selectedGoal == null) _buildGoalSelectionOverlay(),

          if (_isResting) _buildRestOverlay(),

          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatTile("EXERCÍCIO", widget.exercise),
                _buildStatTile("SÉRIE", "$_currentSet / $_totalSets"),
                _buildStatTile(
                  widget.exercise == 'CAMINHADA ESTACIONÁRIA' ? "PASSOS" : "REPS",
                  "$_reps / $_targetReps"
                )
              ],
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

  Widget _buildGoalSelectionOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("QUAL SEU OBJETIVO?", style: GoogleFonts.orbitron(color: WelcomeScreen.panoOrange, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("Escolha uma opção para a TerlineT te orientar", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 30),
            _buildGoalButton("Emagrecer", "Alta queima calórica", Icons.local_fire_department),
            const SizedBox(height: 15),
            _buildGoalButton("Ganhar Massa", "Foco em hipertrofia", Icons.fitness_center),
            const SizedBox(height: 15),
            _buildGoalButton("Resistência", "Mais fôlego e força", Icons.timer),
          ],
        ),
      ),
    );
  }

  Widget _buildRestOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer, color: WelcomeScreen.panoOrange, size: 80),
            const SizedBox(height: 20),
            Text("TEMPO DE DESCANSO", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("00:${_restSeconds.toString().padLeft(2, '0')}", style: GoogleFonts.orbitron(color: WelcomeScreen.panoOrange, fontSize: 60, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            const Text("Recupere o fôlego e mantenha-se hidratado", style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 40),
            Text("PRÓXIMA SÉRIE: $_currentSet / $_totalSets", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalButton(String title, String subtitle, IconData icon) {
    return InkWell(
      onTap: () => _selectGoal(title),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: WelcomeScreen.panoOrange.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, color: WelcomeScreen.panoOrange, size: 30),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
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

    const double videoAspect = 4 / 3;
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
