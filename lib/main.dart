import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'database_service.dart';

// Background task setup
@pragma('vm:entry-point')
void checkAlarmStatus() async {
  final dbService = DatabaseService();
  final values = await dbService.getValues();

  if (values['HomeStatus'] == 'Sound detected' ||
      values['HomeStatus'] == 'Motion detected') {
    // Trigger alarm in background
    final player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(AssetSource('audio/alert_sound.mp3'));

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [500, 1000], repeat: -1);
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AndroidAlarmManager.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home Security',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeSecurityDashboard(),
    );
  }
}

class HomeSecurityDashboard extends StatefulWidget {
  const HomeSecurityDashboard({super.key});

  @override
  State<HomeSecurityDashboard> createState() => _HomeSecurityDashboardState();
}

class _HomeSecurityDashboardState extends State<HomeSecurityDashboard>
    with WidgetsBindingObserver {
  final DatabaseService _dbService = DatabaseService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  late Map<String, dynamic> _values = {
    'Activation': 'OFF',
    'HomeStatus': 'Home is Safe',
    'Password': '1234',
    'Door': 'OPEN',
  };
  bool _isLoading = true;
  bool _showPassword = false;
  bool _isAlarmActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAudio();
    _refreshValues();
    _startBackgroundService();
  }

  void _setupAudio() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    _audioPlayer.onPlayerComplete.listen((_) {
      if (_isAlarmActive) _audioPlayer.resume();
    });
  }

  void _startBackgroundService() async {
    await AndroidAlarmManager.periodic(
      const Duration(seconds: 15),
      0,
      checkAlarmStatus,
      exact: true,
      wakeup: true,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _startBackgroundService();
    } else if (state == AppLifecycleState.resumed) {
      AndroidAlarmManager.cancel(0);
    }
  }

  Future<void> _refreshValues() async {
    setState(() => _isLoading = true);
    final values = await _dbService.getValues();
    if (mounted) {
      setState(() {
        _values = values;
        _isLoading = false;
      });
      _handleStatusUpdate(_values['HomeStatus']);
    }
  }

  void _handleStatusUpdate(String status) {
    if ((status == 'Sound detected' || status == 'Motion detected') &&
        _values['Activation'] == 'ON') {
      _triggerAlarm();
    } else {
      _stopAlarm();
    }
  }

  Future<void> _triggerAlarm() async {
    if (!_isAlarmActive) {
      _isAlarmActive = true;
      await _audioPlayer.play(AssetSource('audio/alert_sound.mp3'));
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [500, 1000], repeat: -1);
      }
    }
  }

  Future<void> _stopAlarm() async {
    if (_isAlarmActive) {
      _isAlarmActive = false;
      await _audioPlayer.stop();
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.cancel();
      }
      await _dbService.updateValue('HomeStatus', 'Home is Safe');
      _refreshValues();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioPlayer.dispose();
    super.dispose();
  }

  // Add this new widget
  Widget _buildStopAlarmButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 20),
      child: ElevatedButton.icon(
        icon: const Icon(Icons.alarm_off, size: 34),
        label: const Text('STOP ALARM', style: TextStyle(fontSize: 20)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
          backgroundColor: Colors.red.shade700,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        onPressed: _stopAlarm,
      ),
    );
  }

  // Modify the alarm control to stop alarm when disarming
  Widget _buildAlarmControl() {
    final isActive = _values['Activation'] == 'ON';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 20),
      child: ElevatedButton.icon(
        icon: Icon(
          isActive
              ? Icons.security_rounded
              : Icons.security_update_good_rounded,
          size: 34,
        ),
        label: Text(
          isActive ? 'DISARM SECURITY' : 'ACTIVATE SECURITY',
          style: const TextStyle(fontSize: 20),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
          backgroundColor:
              isActive ? Colors.red.shade100 : Colors.grey.shade200,
          foregroundColor:
              isActive ? Colors.red.shade800 : Colors.grey.shade800,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(
              color: isActive ? Colors.red : Colors.grey,
              width: 2,
            ),
          ),
        ),
        onPressed: () async {
          final newValue = isActive ? 'OFF' : 'ON';
          final success = await _dbService.updateValue('Activation', newValue);

          if (mounted) {
            if (success) {
              if (newValue == 'OFF') _stopAlarm();
              _refreshValues();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to update the alarm status.'),
                ),
              );
            }
          }
        },
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final status = _values['HomeStatus']?.toString() ?? 'Home is Safe';
    Color statusColor;
    IconData statusIcon;
    String statusMessage;

    switch (status) {
      case 'Sound detected':
        statusColor = Colors.orange;
        statusIcon = Icons.hearing_rounded;
        statusMessage = 'Sound Detected!';
        break;
      case 'Motion detected':
        statusColor = Colors.deepOrange;
        statusIcon = Icons.directions_run_rounded;
        statusMessage = 'Motion Detected!';
        break;
      case 'Home is Safe':
      default:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
        statusMessage = 'Home is Safe';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: statusColor, width: 2),
      ),
      child: Column(
        children: [
          Icon(statusIcon, color: statusColor, size: 40),
          const SizedBox(height: 10),
          Text(
            statusMessage,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
          if (status != 'Home is Safe')
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                'Security Alert!',
                style: TextStyle(color: statusColor, fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }

  // Keep existing _buildStatusIndicator, _buildPasswordSection, and _changePassword methods
  // ... [rest of the existing code remains the same]
  Widget _buildPasswordSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Security Password',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _showPassword ? _values['Password'] : '••••••••',
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed:
                      () => setState(() => _showPassword = !_showPassword),
                ),
              ],
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.lock_reset),
              label: const Text('Change Password'),
              onPressed: _changePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade100,
                foregroundColor: Colors.blue.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _changePassword() {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Change Security Password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Enter New Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Password must be 4-8 characters',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (passwordController.text.length >= 4) {
                    final success = await _dbService.updateValue(
                      'Password',
                      passwordController.text,
                    );

                    if (mounted) {
                      if (success) {
                        _refreshValues();
                        Navigator.pop(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to update password'),
                          ),
                        );
                      }
                    }
                  }
                },
                child: const Text('Change'),
              ),
            ],
          ),
    );
  }

  // New method to handle door state update
  void _handleDoorStateUpdate(String newState) {
    setState(() {
      _values['Door'] = newState;
    });
  }

  // New method to toggle door
  Future<void> _toggleDoor() async {
    final success = await _dbService.toggleDoor();

    if (mounted) {
      if (success) {
        _refreshValues();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to toggle the door.')),
        );
      }
    }
  }

  // New widget for door control button
  Widget _buildDoorControl() {
    final doorState = _values['Door']?.toString().toUpperCase() ?? 'CLOSED';
    String buttonText = doorState == 'OPEN' ? 'Close Door' : 'Open Door';
    IconData icon = doorState == 'OPEN' ? Icons.lock_open : Icons.lock;
    Color backgroundColor =
        doorState == 'OPEN' ? Colors.red.shade300 : Colors.green.shade300;
    Color foregroundColor =
        doorState == 'OPEN' ? Colors.red.shade800 : Colors.green.shade800;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 20),
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 34),
        label: Text(buttonText, style: const TextStyle(fontSize: 20)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(
              color: doorState == 'OPEN' ? Colors.red : Colors.green,
              width: 2,
            ),
          ),
        ),
        onPressed: _toggleDoor,
      ),
    );
  }

  // Modify build method to include stop button
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Security System'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshValues,
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildStatusIndicator(),
                    _buildAlarmControl(),
                    if (_isAlarmActive) _buildStopAlarmButton(),
                    _buildPasswordSection(),
                    _buildDoorControl(),
                  ],
                ),
              ),
    );
  }
}
