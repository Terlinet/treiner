import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'welcome_screen.dart';

import 'exercise_selection_screen.dart';

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          'MODALIDADE',
          style: GoogleFonts.orbitron(
            color: WelcomeScreen.panoOrange,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [
              WelcomeScreen.panoOrange.withOpacity(0.05),
              Colors.transparent,
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          children: [
            _buildCategoryCard(
              context,
              title: 'MUSCULAÇÃO',
              subtitle: 'Força e Hipertrofia',
              icon: Icons.fitness_center,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ExerciseSelectionScreen(modality: 'Musculação'),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            _buildCategoryCard(
              context,
              title: 'GINÁSTICA',
              subtitle: 'Mobilidade e Condicionamento',
              icon: Icons.accessibility_new,
              onTap: () {
                // Navegar para Ginástica
              },
            ),
            const SizedBox(height: 24),
            _buildCategoryCard(
              context,
              title: 'CICLISMO',
              subtitle: 'Resistência e Cardio',
              icon: Icons.directions_bike,
              onTap: () {
                // Navegar para Ciclismo
              },
            ),
            const SizedBox(height: 24),
            _buildCategoryCard(
              context,
              title: 'CORRIDA',
              subtitle: 'Alta Intensidade e Performance',
              icon: Icons.directions_run,
              onTap: () {
                // Navegar para Corrida
              },
            ),
            const SizedBox(height: 24),
            _buildCategoryCard(
              context,
              title: 'CAMINHADA',
              subtitle: 'Saúde e Bem-estar',
              icon: Icons.directions_walk,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ExerciseSelectionScreen(modality: 'Caminhada'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: WelcomeScreen.panoOrange.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: WelcomeScreen.panoOrange.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: WelcomeScreen.panoOrange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: WelcomeScreen.panoOrange,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.orbitron(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: GoogleFonts.roboto(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: WelcomeScreen.panoOrange,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
