import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'welcome_screen.dart';
import 'body_scan_screen.dart';
import 'outdoor_walking_screen.dart';

class ExerciseSelectionScreen extends StatelessWidget {
  final String modality;
  const ExerciseSelectionScreen({super.key, required this.modality});

  @override
  Widget build(BuildContext context) {
    // Lista de exercícios baseada na modalidade
    final List<Map<String, dynamic>> exercises = _getExercises();

    return Scaffold(
      backgroundColor: WelcomeScreen.panoBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: WelcomeScreen.panoOrange),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          modality.toUpperCase(),
          style: GoogleFonts.orbitron(
            color: WelcomeScreen.panoOrange,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 0.8,
        ),
        itemCount: exercises.length,
        itemBuilder: (context, index) {
          final ex = exercises[index];
          return _buildExerciseCard(context, ex);
        },
      ),
    );
  }

  List<Map<String, dynamic>> _getExercises() {
    if (modality == 'Musculação') {
      return [
        {'name': 'AGACHAMENTO', 'icon': Icons.accessibility_new, 'desc': 'Pernas e Glúteos'},
        {'name': 'ROSCA DIRETA', 'icon': Icons.fitness_center, 'desc': 'Bíceps'},
        {'name': 'SUPINO', 'icon': Icons.horizontal_distribute, 'desc': 'Peitoral'},
        {'name': 'ELEVAÇÃO LATERAL', 'icon': Icons.unfold_more, 'desc': 'Ombros'},
      ];
    }
    if (modality == 'Caminhada') {
      return [
        {'name': 'CAMINHADA ESTACIONÁRIA', 'icon': Icons.accessibility_new, 'desc': 'Uso da IA e Câmera'},
        {'name': 'CAMINHADA AO AR LIVRE', 'icon': Icons.map, 'desc': 'Uso de GPS e Mapas'},
      ];
    }
    return [{'name': 'TREINO LIVRE', 'icon': Icons.flash_on, 'desc': 'Geral'}];
  }

  Widget _buildExerciseCard(BuildContext context, Map<String, dynamic> ex) {
    return InkWell(
      onTap: () {
        if (ex['name'] == 'CAMINHADA AO AR LIVRE') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OutdoorWalkingScreen()),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BodyScanScreen(
                modality: modality,
                exercise: ex['name'],
              ),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: WelcomeScreen.panoOrange.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ex['icon'], color: WelcomeScreen.panoOrange, size: 50),
            const SizedBox(height: 15),
            Text(
              ex['name'],
              textAlign: TextAlign.center,
              style: GoogleFonts.orbitron(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Text(
              ex['desc'],
              style: GoogleFonts.roboto(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
