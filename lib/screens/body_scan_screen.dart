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
  CameraController? _cameraController;
  final RepCounter _repCounter = RepCounter();

  // Pose Detection
  late final PoseDetector _poseDetector;
  bool _isBusy = false;
  CustomPaint? _customPaint;

  CameraStatus _cameraStatus = CameraStatus.loading;
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isSynced = false; // Controle de interação para Web Audio
  String _iaStatus = "SISTEMA INICIANDO";

  final String _hfServerUrl = "https://tertulianoshow-terlinet-treiner.hf.space";

  @override
  void initState() {
    super.initState();
    _poseDetector = PoseDetector(options: PoseDetectorOptions());
    _checkAndInitializeCamera();
  }

  @override
  void dispose() {
    _poseDetector.close();
    _cameraController?.dispose();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _checkAndInitializeCamera() async {
    try {
      if (kIsWeb) {
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
          setState(() { _cameraStatus = CameraStatus.notFound; });
          return;
        }
        _cameraController = CameraController(cameras.first, ResolutionPreset.medium);
        await _cameraController!.initialize();
        setState(() {
          _cameraStatus = CameraStatus.available;
          _iaStatus = "AGUARDANDO SINCRONIZAÇÃO";
        });
        return;
      }

      final status = await Permission.camera.request();
      if (status.isDenied) {
        setState(() { _cameraStatus = CameraStatus.denied; });
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() { _cameraStatus = CameraStatus.notFound; });
        return;
      }

      _cameraController = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
      await _cameraController!.initialize();
      _cameraController!.startImageStream(_processCameraImage);

      if (mounted) {
        setState(() {
          _cameraStatus = CameraStatus.available;
          _iaStatus = "SCANNER ATIVO";
        });
      }
    } catch (e) {
      setState(() { _cameraStatus = CameraStatus.error; });
    }
  }

  // Função para dar o "Start" real (Necessário para áudio no Chrome)
  void _syncSystem() {
    setState(() {
      _isSynced = true;
      _iaStatus = "ORIENTANDO ALUNO";
    });
    _welcomeStudent();
  }

  void _welcomeStudent() {
    String message = "";
    switch (widget.exercise) {
      case 'AGACHAMENTO':
        message = 'Olá! Para o agachamento, apoie o celular a 2 metros de distância. Eu preciso ver seus pés e cabeça. Pode começar quando estiver pronto!';
        break;
      case 'ROSCA DIRETA':
        message = 'Bíceps em foco! Fique de frente para a câmera e mostre seus braços por inteiro. Evite balançar o tronco. Vamos lá!';
        break;
      default:
        message = 'Iniciando treino de ${widget.exercise}. Posicione o celular de forma estável para eu observar seus movimentos!';
    }
    _speakToIA(message);
  }

  // Simulação de movimento para teste no Chrome (PC)
  void _simulateMovement() {
    setState(() {
      _repCounter.count++;
      _iaStatus = "MOVIMENTO DETECTADO";
    });
    if (_repCounter.count % 5 == 0) {
      _speakToIA("Excelente ritmo! Você já completou ${_repCounter.count} repetições. Continue assim!");
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy || kIsWeb) return;
    _isBusy = true;
    // Lógica ML Kit Pose (Nativa Mobile)
    _isBusy = false;
  }

  Future<void> _speakToIA(String userText) async {
    setState(() {
      _isProcessing = true;
      _iaStatus = "IA PENSANDO...";
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
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String? audioBase64 = data['audio'];
        setState(() { _iaStatus = "TREINADOR FALANDO"; });
        if (audioBase64 != null) {
          await _audioPlayer.play(BytesSource(base64Decode(audioBase64)));
        }
      }
    } catch (e) {
      print("Erro na IA: $e");
      setState(() { _iaStatus = "ERRO DE CONEXÃO"; });
    } finally {
      setState(() { _isProcessing = false; });
    }
  }

  // Métodos de Gravação (Voz)
  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final directory = await getTemporaryDirectory();
      await _audioRecorder.start(const RecordConfig(), path: '${directory.path}/query.m4a');
      setState(() { _isRecording = true; _iaStatus = "OUVINDO..."; });
    }
  }

  Future<void> _stopAndSend() async {
    final path = await _audioRecorder.stop();
    setState(() { _isRecording = false; _isProcessing = true; _iaStatus = "ANALISANDO VOZ..."; });
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
          _buildCameraLayer(),

          // Interface de Sincronização (Apenas no início)
          if (!_isSynced) _buildSyncOverlay(),

          // HUD Superior
          Positioned(
            top: 50,
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

          // Botões de Teste para WEB (PC)
          if (kIsWeb && _isSynced) _buildWebTestButtons(),

          // HUD IA Status
          _buildIAStatusPanel(),

          // Microfone
          if (_isSynced) _buildMicButton(),

          // Botão Sair
          Positioned(top: 50, left: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))),
        ],
      ),
    );
  }

  Widget _buildSyncOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.psychology, color: WelcomeScreen.panoOrange, size: 80),
            const SizedBox(height: 20),
            Text("SISTEMA PRONTO", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 24)),
            const SizedBox(height: 10),
            const Text("Clique abaixo para iniciar a IA e as orientações", style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _syncSystem,
              style: ElevatedButton.styleFrom(backgroundColor: WelcomeScreen.panoOrange, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
              child: const Text("INICIAR TREINO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebTestButtons() {
    return Positioned(
      top: 150,
      right: 20,
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: _simulateMovement,
            icon: const Icon(Icons.add),
            label: const Text("SIMULAR REP"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
          ),
          const SizedBox(height: 10),
          const Text("Modo Web: Use para testar IA", style: TextStyle(color: Colors.white24, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildIAStatusPanel() {
    return Positioned(
      bottom: 150,
      left: 30,
      right: 30,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.black87, border: Border.all(color: WelcomeScreen.panoOrange, width: 2), borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(_iaStatus, style: GoogleFonts.orbitron(color: WelcomeScreen.panoOrange, fontSize: 12, fontWeight: FontWeight.bold)),
            if (_isProcessing) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(backgroundColor: Colors.black, color: WelcomeScreen.panoOrange)),
          ],
        ),
      ),
    );
  }

  Widget _buildMicButton() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onLongPressStart: (_) => _startRecording(),
          onLongPressEnd: (_) => _stopAndSend(),
          child: CircleAvatar(
            radius: 40,
            backgroundColor: _isRecording ? Colors.red : WelcomeScreen.panoOrange,
            child: Icon(_isProcessing ? Icons.sync : Icons.mic, color: Colors.black, size: 40),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraLayer() {
    if (_cameraStatus == CameraStatus.loading) return const Center(child: CircularProgressIndicator(color: WelcomeScreen.panoOrange));
    if (_cameraStatus != CameraStatus.available || _cameraController == null) return Container(color: Colors.black);
    return Stack(fit: StackFit.expand, children: [CameraPreview(_cameraController!), if (_customPaint != null) _customPaint!]);
  }

  Widget _buildStatTile(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.orbitron(color: WelcomeScreen.panoOrange, fontSize: 10)),
      Text(value, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
    ]);
  }
}
