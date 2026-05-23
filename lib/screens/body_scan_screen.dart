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
          _iaStatus = "WEB MODE (SKELETON EM MOBILE)";
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

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      _cameraController!.startImageStream(_processCameraImage);

      if (mounted) {
        setState(() {
          _cameraStatus = CameraStatus.available;
          _iaStatus = "SCANNER ATIVO";
        });
        _welcomeStudent();
      }
    } catch (e) {
      setState(() { _cameraStatus = CameraStatus.error; });
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isBusy) return;
    _isBusy = true;

    try {
      // Implementação real exigiria InputImage.fromBytes para Mobile
      // poses = await _poseDetector.processImage(inputImage);
      if (mounted) setState(() {});
    } catch (e) {
      print("Erro no processamento: $e");
    } finally {
      _isBusy = false;
    }
  }

  void _welcomeStudent() {
    String message = "";

    // Orientações específicas baseadas no exercício
    switch (widget.exercise) {
       Apoie o celular em um local firme a cerca de 2 metros. Afaste-se até que eu consiga ver seus pés e cabeça. Mantenha as costas retas e pode começar!';
        break;
      case 'ROSCA DIRETA':
        message = 'Vamos focar no bíceps! Fique de frente para a câmera, a uma distância que eu veja seus braços por inteiro. Evite balançar o corpo durante a subida. Estou pronto!';
        break;
      case 'ELEVAÇÃO LATERAL':
        message = 'Hora de trabalhar os ombros. Posicione-se de frente, mantenha os braços levemente flexionados e suba até a linha dos ombros. Aguardo seu início!';
        break;
      case 'SUPINO':
        message = 'Para o supino, certifique-se de que o celular está em um ângulo que eu veja seu peito e braços. Mantenha o controle na descida. Vamos lá!';
        break;
      default:
        message = 'Iniciando acompanhamento de ${widget.exercise}. Posicione o dispositivo de forma estável para que eu consiga observar seus movimentos. Estou pronto para contar!';
    }

    setState(() {
      _iaStatus = "CONFIGURANDO POSIÇÃO";
    });

    _speakToIA(message);
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/audio_query.m4a';
        const config = RecordConfig();
        await _audioRecorder.start(config, path: path);
        setState(() {
          _isRecording = true;
          _iaStatus = "OUVINDO...";
        });
      }
    } catch (e) {
      print("Erro ao gravar: $e");
    }
  }

  Future<void> _stopAndSend() async {
    final path = await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _isProcessing = true;
      _iaStatus = "PROCESSANDO VOZ...";
    });
    if (path != null) {
      await _sendAudioToIA(File(path));
    }
  }

  Future<void> _sendAudioToIA(File audioFile) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$_hfServerUrl/voice_query'));
      request.fields['modality'] = widget.exercise;
      request.fields['reps'] = _repCounter.count.toString();
      request.files.add(await http.MultipartFile.fromPath('audio', audioFile.path));

      var response = await request.send();
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var data = jsonDecode(responseData);
        if (data['audio'] != null) {
          setState(() { _iaStatus = "TREINADOR FALANDO"; });
          await _audioPlayer.play(BytesSource(base64Decode(data['audio'])));
        }
      }
    } catch (e) {
      print("Erro ao enviar áudio: $e");
    } finally {
      setState(() {
        _isProcessing = false;
        _iaStatus = "AGUARDANDO COMANDO";
      });
    }
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
      );
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
    } finally {
      setState(() {
        _isProcessing = false;
        _iaStatus = "AGUARDANDO COMANDO";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildCameraLayer(),
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
          Positioned(
            bottom: 150,
            left: 30,
            right: 30,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.black87,
                border: Border.all(color: WelcomeScreen.panoOrange, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    _iaStatus,
                    style: GoogleFonts.orbitron(
                      color: WelcomeScreen.panoOrange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_isProcessing)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.black,
                        color: WelcomeScreen.panoOrange,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) => _stopAndSend(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: _isRecording ? 100 : 80,
                  width: _isRecording ? 100 : 80,
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.redAccent : WelcomeScreen.panoOrange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording ? Colors.red : WelcomeScreen.panoOrange).withOpacity(0.5),
                        blurRadius: _isRecording ? 40 : 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isProcessing ? Icons.sync : (_isRecording ? Icons.mic : Icons.mic_none),
                    color: Colors.black,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 125,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                _isRecording ? "SOLTE PARA ENVIAR" : "SEGURE PARA FALAR",
                style: GoogleFonts.orbitron(color: Colors.white54, fontSize: 10),
              ),
            ),
          ),
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraLayer() {
    if (_cameraStatus == CameraStatus.loading) {
      return const Center(child: CircularProgressIndicator(color: WelcomeScreen.panoOrange));
    }
    if (_cameraStatus == CameraStatus.denied) {
      return _buildErrorState(Icons.lock_outline, "PERMISSÃO NEGADA", "Ative a câmera nas configurações.");
    }
    if (_cameraStatus == CameraStatus.notFound) {
      return _buildErrorState(Icons.videocam_off_outlined, "CÂMERA NÃO ENCONTRADA", "Conecte uma câmera para treinar.");
    }
    if (_cameraStatus == CameraStatus.error || _cameraController == null) {
      return _buildErrorState(Icons.error_outline, "ERRO NO SISTEMA", "Reinicie o aplicativo.");
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_cameraController!),
        if (_customPaint != null) _customPaint!,
      ],
    );
  }

  Widget _buildErrorState(IconData icon, String title, String sub) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: WelcomeScreen.panoOrange, size: 80),
          const SizedBox(height: 20),
          Text(title, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 20)),
          const SizedBox(height: 10),
          Text(sub, style: GoogleFonts.roboto(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _checkAndInitializeCamera,
            style: ElevatedButton.styleFrom(backgroundColor: WelcomeScreen.panoOrange),
            child: const Text("TENTAR NOVAMENTE", style: TextStyle(color: Colors.black)),
          )
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.orbitron(color: WelcomeScreen.panoOrange, fontSize: 10)),
        Text(value, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
