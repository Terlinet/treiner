import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'welcome_screen.dart';

class OutdoorWalkingScreen extends StatefulWidget {
  final bool isRunning;
  const OutdoorWalkingScreen({super.key, this.isRunning = false});

  @override
  State<OutdoorWalkingScreen> createState() => _OutdoorWalkingScreenState();
}

class _OutdoorWalkingScreenState extends State<OutdoorWalkingScreen> {
  bool _isTracking = false;
  double _distance = 0.0;
  double _speed = 0.0;
  Duration _duration = Duration.zero;
  Timer? _timer;
  Position? _lastPosition;

  StreamSubscription<Position>? _positionStream;

  Future<void> _startTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    setState(() {
      _isTracking = true;
      _distance = 0.0;
      _duration = Duration.zero;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _duration += const Duration(seconds: 1);
      });
    });

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      if (_lastPosition != null) {
        double d = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        setState(() {
          _distance += d;
          _speed = position.speed * 3.6; // m/s to km/h
        });
      }
      _lastPosition = position;
    });
  }

  void _stopTracking() {
    _timer?.cancel();
    _positionStream?.cancel();
    setState(() {
      _isTracking = false;
      _speed = 0.0;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WelcomeScreen.panoBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isRunning ? 'CORRIDA AO AR LIVRE' : 'CAMINHADA AO AR LIVRE',
          style: GoogleFonts.orbitron(color: WelcomeScreen.panoOrange, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: Stack(
        children: [
          // Background Aesthetic
          Positioned.fill(
            child: Opacity(
              opacity: 0.1,
              child: Icon(widget.isRunning ? Icons.directions_run : Icons.map, size: 400, color: WelcomeScreen.panoOrange),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                _buildStatCard(),
                const Spacer(),
                _buildControlPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WelcomeScreen.panoOrange.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            _isTracking ? "ATIVIDADE EM CURSO" : "PRONTO PARA COMEÇAR",
            style: GoogleFonts.orbitron(color: WelcomeScreen.panoOrange, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildLargeStat("DISTÂNCIA", "${(_distance / 1000).toStringAsFixed(2)}", "km"),
              _buildLargeStat("TEMPO", _formatDuration(_duration), ""),
            ],
          ),
          const Divider(color: Colors.white10, height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSmallStat("VELOCIDADE", "${_speed.toStringAsFixed(1)}", "km/h"),
              _buildSmallStat("RITMO MÉDIO", _calculatePace(), "min/km"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLargeStat(String label, String value, String unit) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(color: WelcomeScreen.panoOrange, fontSize: 14)),
            ]
          ],
        ),
      ],
    );
  }

  Widget _buildSmallStat(String label, String value, String unit) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        const SizedBox(height: 4),
        Text("$value $unit", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildControlPanel() {
    return Column(
      children: [
        if (!_isTracking)
          _buildActionButton(
            "INICIAR CAMINHADA",
            Icons.play_arrow,
            WelcomeScreen.panoOrange,
            _startTracking,
          )
        else
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  "PARAR",
                  Icons.stop,
                  Colors.redAccent,
                  _stopTracking,
                ),
              ),
            ],
          ),
        const SizedBox(height: 20),
        const Text(
          "O GPS consome mais bateria. Certifique-se de estar ao ar livre para melhor precisão.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white24, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildActionButton(String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Text(
              title,
              style: GoogleFonts.orbitron(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  String _calculatePace() {
    if (_distance < 10 || _duration.inSeconds < 1) return "0:00";
    double km = _distance / 1000;
    double minutesPerKm = (_duration.inSeconds / 60) / km;
    int mins = minutesPerKm.floor();
    int secs = ((minutesPerKm - mins) * 60).round();
    return "$mins:${secs.toString().padLeft(2, "0")}";
  }
}
