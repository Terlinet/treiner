import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'welcome_screen.dart';

import 'package:camera/camera.dart';
import '../utils/pose_utils.dart';
import 'welcome_screen.dart';

import 'package:permission_handler/permission_handler.dart';

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
  CameraController? _cameraController;
  final RepCounter _repCounter = RepCounter();

  CameraStatus _cameraStatus = CameraStatus.loading;
  bool _isListening = false;
  bool _isProcessing = false;
  String _iaStatus = "SISTEMA INICIANDO";

  // URL do seu servidor no Hugging Face
  final String _hfServerUrl = "https://tertulianoshow-terlinet-treiner.hf.space/query";

  @override
  void initState() {
    super.initState();
    _checkAndInitializeCamera();
  }

  Future<void> _checkAndInitializeCamera() async {
    try {
      // 1. Solicitar permissão de câmera
      final status = await Permission.camera.request();

      if (status.isDenied || status.isPermanentlyDenied) {
        setState(() {
          _cameraStatus = CameraStatus.denied;
          _iaStatus = "ACESSO NEGADO";
        });
        return;
      }

      // 2. Verificar hardware
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _cameraStatus = CameraStatus.notFound;
          _iaStatus = "CÂMERA NÃO DETECTADA";
        });
        return;
      }

      // 3. Inicializar
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _cameraStatus = CameraStatus.available;
          _iaStatus = "SCANNER ATIVO";
        });
        _welcomeStudent();
      }
    } catch (e) {
      setState(() {
        _cameraStatus = CameraStatus.error;
        _iaStatus = "ERRO DE HARDWARE";
      });
    }
  }

  void _welcomeStudent() {
    _speakToIA("Conexão estabelecida. Sistema de visão pronto para o treino de ${widget.exercise}.");
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _speakToIA(String userText) async {
    setState(() {
      _isProcessing = true;
      _iaStatus = "IA PENSANDO...";
    });

    try {
      final response = await http.post(
        Uri.parse(_hfServerUrl),
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

        setState(() {
          _iaStatus = "TREINADOR FALANDO";
        });

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
          // Camada da Câmera com Estados de Erro
          _buildCameraLayer(),

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

          // Painel de Status da IA (Visual Panobianco)
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

          // Botão de Interação por Voz
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => _speakToIA("Olá treinador, como está minha postura?"),
                child: Container(
                  height: 80,
                  width: 80,
                  decoration: BoxDecoration(
                    color: _isProcessing ? Colors.grey : WelcomeScreen.panoOrange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: WelcomeScreen.panoOrange.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isProcessing ? Icons.sync : Icons.mic,
                    color: Colors.black,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),

          // Botão Sair
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

    return SizedBox.expand(
      child: CameraPreview(_cameraController!),
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
        Text(
          label,
          style: GoogleFonts.orbitron(color: WelcomeScreen.panoOrange, fontSize: 10),
        ),
        Text(
          value,
          style: GoogleFonts.orbitron(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
