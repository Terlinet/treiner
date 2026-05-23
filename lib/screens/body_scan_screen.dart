import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'welcome_screen.dart';
import 'package:camera/camera.dart';
import '../utils/pose_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../utils/pose_painter.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import '../services/js_bridge.dart' if (dart.library.html) '../services/js_bridge.dart';

enum CameraStatus { loading, available, denied, notFound, error }

class BodyScanScreen extends StatefulWidget {
  final String modality;
  final String exercise;
  const BodyScanScreen({super.key, required this.modality, required this.exercise});

  @override
  State<BodyScanScreen> createState() => _BodyScanScreenState();
}

class _BodyScanScreenState extends State<BodyScanScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final TextEditingController _textController = TextEditingController();
  CameraController? _cameraController;
  final RepCounter _repCounter = RepCounter();

  CameraStatus _cameraStatus = CameraStatus.loading;
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isSynced = false;
  String _iaStatus = "SISTEMA INICIANDO";

  final String _hfServerUrl = "https://tertulianoshow-terlinet-treiner.hf.space";

  @override
  void initState() {
    super.initState();
    _checkAndInitializeCamera();

    if (kIsWeb) {
      onPoseDetected = (String results) {
        // Lógica para processar pontos vindos do JS
        // Para simplificar, vamos apenas detectar se há pose
        if (_isSynced && _iaStatus == "OUVINDO TERLINET") {
          setState(() { _iaStatus = "ALUNO DETECTADO"; });
        }
      };
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _checkAndInitializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() { _cameraStatus = CameraStatus.notFound; });
        return;
      }

      final frontCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high, // Maior resolução para melhor detecção
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (kIsWeb) {
        // Inicializa MediaPipe no Web enviando o elemento de vídeo
        // O plugin camera do Flutter Web cria um video element que podemos tentar capturar
        // Mas por praticidade, o initMediaPipe no JS pode buscar o primeiro video da página
        initMediaPipe(null);
      }

      if (mounted) {
        setState(() {
          _cameraStatus = CameraStatus.available;
          _iaStatus = kIsWeb ? "AGUARDANDO SINCRONIZAÇÃO" : "SCANNER ATIVO";
        });
      }
    } catch (e) {
      setState(() { _cameraStatus = CameraStatus.error; });
    }
  }

  void _syncSystem() {
    setState(() {
      _isSynced = true;
      _iaStatus = "OUVINDO TERLINET";
    });
    _speakToIA("INICIAR");
  }

  void _simulateMovement() {
    setState(() {
      _repCounter.count++;
      _iaStatus = "MOVIMENTO DETECTADO";
    });
    if (_repCounter.count % 5 == 0) {
      _speakToIA("Incrível! Você já completou ${_repCounter.count} repetições. Mantenha o ritmo!");
    }
  }

  Future<void> _speakToIA(String userText) async {
    setState(() {
      _isProcessing = true;
      _iaStatus = "TERLINET PENSANDO...";
    });
    try {
      final response = await http.post(
        Uri.parse('$_hfServerUrl/query'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "text": userText,
          "modality": widget.exercise,
          "reps": _repCounter.count,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() { _iaStatus = "TERLINET FALANDO"; });
        if (data['audio'] != null) {
          await _audioPlayer.play(BytesSource(base64Decode(data['audio'])));
        }
      }
    } catch (e) {
      setState(() { _iaStatus = "ERRO DE CONEXÃO"; });
    } finally {
      setState(() { _isProcessing = false; });
    }
  }

  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final directory = await getTemporaryDirectory();
      await _audioRecorder.start(const RecordConfig(), path: '${directory.path}/query.m4a');
      setState(() { _isRecording = true; _iaStatus = "OUVINDO..."; });
    }
  }

  Future<void> _stopAndSend() async {
    final path = await _audioRecorder.stop();
    setState(() { _isRecording = false; _isProcessing = true; _iaStatus = "ANALISANDO..."; });
    if (path != null) {
      var request = http.MultipartRequest('POST', Uri.parse('$_hfServerUrl/voice_query'));
      request.fields['modality'] = widget.exercise;
      request.fields['reps'] = _repCounter.count.toString();
      request.files.add(await http.MultipartFile.fromPath('audio', path));
      var response = await request.send();
      if (response.statusCode == 200) {
        var data = jsonDecode(await response.stream.bytesToString());
        if (data['audio'] != null) {
          await _audioPlayer.play(BytesSource(base64Decode(data['audio'])));
        }
      }
      setState(() { _isProcessing = false; _iaStatus = "AGUARDANDO"; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camada da Câmera (Fills the whole screen)
          _buildCameraLayer(),

          if (!_isSynced) _buildSyncOverlay(),

          // HUD Superior
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatTile("EXERCÍCIO", widget.exercise),
                _buildStatTile("REPETIÇÕES", _repCounter.count.toString()),
              ],
            ),
          ),

          // Interação
          if (_isSynced) _buildInteractionPanel(),

          // Botão Sair
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context)
            )
          ),
        ],
      ),
    );
  }

  Widget _buildCameraLayer() {
    if (_cameraStatus == CameraStatus.loading) {
      return const Center(child: CircularProgressIndicator(color: WelcomeScreen.panoOrange));
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Container(color: Colors.black);
    }

    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * _cameraController!.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return Center(
      child: Transform.scale(
        scale: scale,
        child: CameraPreview(_cameraController!),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: WelcomeScreen.panoOrange,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
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
          // Status IA
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              border: Border.all(color: WelcomeScreen.panoOrange.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(10)
            ),
            child: Column(
              children: [
                Text(_iaStatus, style: GoogleFonts.orbitron(color: WelcomeScreen.panoOrange, fontSize: 10, fontWeight: FontWeight.bold)),
                if (_isProcessing) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(backgroundColor: Colors.black, color: WelcomeScreen.panoOrange)),
              ],
            ),
          ),
          const SizedBox(height: 15),
          // Chat Bar
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: WelcomeScreen.panoOrange.withOpacity(0.5))
                  ),
                  child: TextField(
                    controller: _textController,
                    onSubmitted: (val) { if(val.isNotEmpty) { _speakToIA(val); _textController.clear(); } },
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: "Fale com a TerlineT...",
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                      border: InputBorder.none
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) => _stopAndSend(),
                onTap: () { if(_textController.text.isNotEmpty) { _speakToIA(_textController.text); _textController.clear(); } },
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: _isRecording ? Colors.red : WelcomeScreen.panoOrange,
                  child: Icon(_isProcessing ? Icons.sync : (_textController.text.isEmpty ? Icons.mic : Icons.send), color: Colors.black)
                ),
              ),
            ],
          ),
          if (kIsWeb) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextButton(
              onPressed: _simulateMovement,
              child: const Text("SIMULAR REPETIÇÃO (TESTE WEB)", style: TextStyle(color: Colors.white24, fontSize: 10))
            ),
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
