import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'audio_keyword_screen.dart'; // TAMBAHAN: import audio screen

List<CameraDescription>? cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera error: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CV Model Training',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF4DB6AC),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4DB6AC),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const CVWorkspaceScreen(),
    );
  }
}

class AppColors {
  static const Color primary = Color(0xFF4DB6AC);
  static const Color primaryDark = Color(0xFF26A69A);
  static const Color accent = Color(0xFF80CBC4);
  static const Color background = Color(0xFFF5F5F5);
  static const Color cardBackground = Color(0xFFE0F2F1);
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
}

class CVWorkspaceScreen extends StatefulWidget {
  const CVWorkspaceScreen({super.key});

  @override
  State<CVWorkspaceScreen> createState() => _CVWorkspaceScreenState();
}

class _CVWorkspaceScreenState extends State<CVWorkspaceScreen> with TickerProviderStateMixin {
  static const platform = MethodChannel('cv_training/model');
  
  CameraController? _camera;
  bool _cameraReady = false;
  bool _modelLoaded = false;
  
  bool _showClassPanel = false;
  bool _showConsole = true;
  bool _isTrainingMode = true;
  
  late AnimationController _classPanelController;
  late Animation<Offset> _classPanelSlide;
  
  String _selectedClass = '1';
  final Map<String, String> _classNames = {
    '1': 'Object 1',
    '2': 'Object 2',
    '3': 'Object 3',
    '4': 'Object 4',
    '5': 'Object 5',
  };
  final Map<String, int> _samples = {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0};
  int _totalSamples = 0;
  bool _isTraining = false;
  double _loss = 0.0;
  
  List<Map<String, dynamic>> _results = [];
  Timer? _inferenceTimer;
  bool _isCapturing = false;
  
  final List<String> _consoleMessages = [];
  final ScrollController _consoleScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _classPanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _classPanelSlide = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _classPanelController,
      curve: Curves.easeInOut,
    ));
    _init();
  }

  Future<void> _init() async {
    _addConsoleLog('🚀 Initializing CV workspace...');
    await Permission.camera.request();
    await _loadModel();
    await _initCamera();
  }

  Future<void> _loadModel() async {
    try {
      final result = await platform.invokeMethod('initModel');
      setState(() => _modelLoaded = result == true);
      _addConsoleLog('✅ Model loaded successfully');
    } catch (e) {
      _addConsoleLog('❌ Model error: $e');
    }
  }

  Future<void> _initCamera() async {
    if (cameras == null || cameras!.isEmpty) return;
    
    _camera = CameraController(cameras![0], ResolutionPreset.low, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    
    try {
      await _camera!.initialize();
      await _camera!.setFlashMode(FlashMode.off);
      try {
        await _camera!.setFocusMode(FocusMode.locked);
      } catch (e) {
        await _camera!.setFocusMode(FocusMode.auto);
      }
      setState(() => _cameraReady = true);
      _addConsoleLog('📷 Camera ready');
    } catch (e) {
      _addConsoleLog('❌ Camera error: $e');
    }
  }

  void _addConsoleLog(String message) {
    if (!mounted) return;
    setState(() {
      _consoleMessages.add('[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_consoleMessages.length > 50) _consoleMessages.removeAt(0);
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _consoleScroll.hasClients) {
        _consoleScroll.animateTo(_consoleScroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _capture() async {
    if (_camera == null || _isCapturing) return;
    _isCapturing = true;
    try {
      final image = await _camera!.takePicture();
      setState(() {
        _samples[_selectedClass] = (_samples[_selectedClass] ?? 0) + 1;
        _totalSamples++;
      });
      _addConsoleLog('📸 Captured sample for ${_classNames[_selectedClass]}');
      final bytes = await image.readAsBytes();
      _processImageAsync(bytes);
    } catch (e) {
      _addConsoleLog('❌ Capture error: $e');
    }
    _isCapturing = false;
  }

  Future<void> _processImageAsync(Uint8List bytes) async {
    try {
      final imageData = _preprocessImage(bytes);
      await platform.invokeMethod('addSample', {'imageData': imageData, 'className': _selectedClass});
      _addConsoleLog('✅ Sample processed');
    } catch (e) {
      _addConsoleLog('❌ Process error: $e');
    }
  }

  List<double> _preprocessImage(Uint8List imageBytes) {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) return [];
    image = img.bakeOrientation(image);
    final size = image.width < image.height ? image.width : image.height;
    final offsetX = (image.width - size) ~/ 2;
    final offsetY = (image.height - size) ~/ 2;
    img.Image cropped = img.copyCrop(image, x: offsetX, y: offsetY, width: size, height: size);
    img.Image resized = img.copyResize(cropped, width: 224, height: 224, interpolation: img.Interpolation.nearest);
    final buffer = <double>[];
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
        buffer.add(pixel.r / 255.0);
        buffer.add(pixel.g / 255.0);
        buffer.add(pixel.b / 255.0);
      }
    }
    return buffer;
  }

  Future<void> _renameClass(String classId) async {
    final controller = TextEditingController(text: _classNames[classId]);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Rename ${_classNames[classId]}'),
        content: TextField(controller: controller, decoration: InputDecoration(hintText: 'Enter class name', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white), child: const Text('Save')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      setState(() => _classNames[classId] = newName);
      _addConsoleLog('📝 Renamed class $classId to "$newName"');
    }
  }

  Future<void> _train() async {
    if (_totalSamples < 5) {
      _addConsoleLog('⚠️ Need at least 5 samples');
      return;
    }
    try {
      final info = await platform.invokeMethod('getSamplesInfo');
      final perClass = info['perClass'] as Map?;
      if (perClass == null || perClass.isEmpty) {
        _addConsoleLog('⚠️ No samples found');
        return;
      }
      final nonEmptyClasses = perClass.values.where((v) => v > 0).length;
      if (nonEmptyClasses < 2) {
        _addConsoleLog('⚠️ Need samples from at least 2 classes');
        return;
      }
      final epochs = 20;
      setState(() => _isTraining = true);
      _addConsoleLog('🎓 Training started with $epochs epochs...');
      final result = await platform.invokeMethod('train', {'epochs': epochs});
      if (result is Map) {
        final loss = (result['loss'] as num).toDouble();
        setState(() {
          _loss = loss;
          _isTraining = false;
        });
        _addConsoleLog('🎉 Training completed! Loss: ${_loss.toStringAsFixed(4)}');
      }
    } catch (e) {
      setState(() => _isTraining = false);
      _addConsoleLog('❌ Training failed: $e');
    }
  }

  Future<void> _resetModel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.warning_amber, color: AppColors.warning), SizedBox(width: 8), Text('Reset Model?')]),
        content: const Text('This will clear all samples and reset the model.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white), child: const Text('Reset')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await platform.invokeMethod('resetModel');
      setState(() {
        _samples.updateAll((key, value) => 0);
        _totalSamples = 0;
        _loss = 0.0;
        _results.clear();
      });
      _addConsoleLog('🔄 Model reset successfully');
    } catch (e) {
      _addConsoleLog('❌ Reset failed: $e');
    }
  }

  void _startInference() {
    _addConsoleLog('🔮 Inference mode activated');
    _inferenceTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      if (_isCapturing) return;
      _isCapturing = true;
      try {
        final image = await _camera!.takePicture();
        final bytes = await image.readAsBytes();
        final imageData = _preprocessImage(bytes);
        final result = await platform.invokeMethod('classify', {'imageData': imageData});
        if (result is List) {
          final probs = result.cast<double>();
          setState(() {
            _results = List.generate(5, (i) => {'id': '${i + 1}', 'label': _classNames['${i + 1}'] ?? 'Class ${i + 1}', 'confidence': probs[i]})..sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));
          });
        }
      } catch (e) {
        debugPrint('Inference error: $e');
      }
      _isCapturing = false;
    });
  }

  void _stopInference() {
    _inferenceTimer?.cancel();
    setState(() => _results.clear());
    _addConsoleLog('⏸️ Inference mode stopped');
  }

  void _toggleMode() {
    setState(() {
      _isTrainingMode = !_isTrainingMode;
      _isTrainingMode ? _stopInference() : _startInference();
    });
  }

  @override
  void dispose() {
    _inferenceTimer?.cancel();
    _camera?.dispose();
    _classPanelController.dispose();
    _consoleScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildCameraView(),
          if (_showClassPanel) _buildClassPanel(),
          if (_showConsole) _buildConsole(),
          if (!_isTrainingMode && _results.isNotEmpty) _buildResultsPanel(),
          _buildTopControls(),
          _buildFloatingActions(),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (!_cameraReady || _camera == null) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    return SizedBox.expand(child: CameraPreview(_camera!));
  }

  Widget _buildTopControls() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.accent, width: 2)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModeButton('Training', Icons.school, _isTrainingMode),
                _buildModeButton('Inference', Icons.psychology, !_isTrainingMode),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20), border: Border.all(color: _modelLoaded ? AppColors.success : AppColors.error, width: 2)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_modelLoaded ? Icons.check_circle : Icons.error, color: _modelLoaded ? AppColors.success : AppColors.error, size: 16),
                const SizedBox(width: 6),
                Text('$_totalSamples samples', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(String label, IconData icon, bool isActive) {
    return GestureDetector(
      onTap: _toggleMode,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: isActive ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(18)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? Colors.white : AppColors.accent, size: 16),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: isActive ? Colors.white : AppColors.accent, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActions() {
    return Positioned(
      right: 16,
      top: MediaQuery.of(context).size.height * 0.3,
      child: Column(
        children: [
          // TAMBAHAN: Tombol Audio (kecil di paling atas)
          _buildActionButton(
            icon: Icons.mic,
            color: AppColors.warning,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioKeywordScreen())),
          ),
          const SizedBox(height: 12),
          
          // Sisanya tetap sama
          _buildActionButton(icon: _showClassPanel ? Icons.close : Icons.dashboard, color: AppColors.primary, onTap: () {
            setState(() {
              _showClassPanel = !_showClassPanel;
              _showClassPanel ? _classPanelController.forward() : _classPanelController.reverse();
            });
          }),
          const SizedBox(height: 12),
          if (_isTrainingMode) ...[
            _buildActionButton(icon: Icons.camera_alt, color: AppColors.success, onTap: _capture, size: 56),
            const SizedBox(height: 12),
            _buildActionButton(icon: _isTraining ? Icons.hourglass_empty : Icons.play_arrow, color: _isTraining ? AppColors.warning : AppColors.primaryDark, onTap: _isTraining ? null : _train),
          ],
          const SizedBox(height: 12),
          _buildActionButton(icon: _showConsole ? Icons.keyboard_arrow_down : Icons.terminal, color: AppColors.accent, onTap: () => setState(() => _showConsole = !_showConsole)),
          const SizedBox(height: 12),
          _buildActionButton(icon: Icons.restart_alt, color: AppColors.error, onTap: _resetModel),
        ],
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required Color color, required VoidCallback? onTap, double size = 48}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), shape: BoxShape.circle, border: Border.all(color: color, width: 3)),
        child: Icon(icon, color: color, size: size * 0.5),
      ),
    );
  }

  Widget _buildClassPanel() {
    return Positioned(
      left: 0,
      top: MediaQuery.of(context).size.height * 0.2,
      bottom: _showConsole ? 180 : 20,
      child: SlideTransition(
        position: _classPanelSlide,
        child: Container(
          width: 200,
          margin: const EdgeInsets.only(left: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.cardBackground.withOpacity(0.95), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.accent, width: 2)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Classes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: _classNames.keys.map((classId) {
                    final isSelected = _selectedClass == classId;
                    final count = _samples[classId] ?? 0;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedClass = classId),
                      onLongPress: () => _renameClass(classId),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: isSelected ? AppColors.primary : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isSelected ? AppColors.primaryDark : AppColors.accent, width: 2)),
                        child: Row(
                          children: [
                            Expanded(child: Text(_classNames[classId]!, style: TextStyle(color: isSelected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: isSelected ? Colors.white.withOpacity(0.3) : AppColors.accent.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                              child: Text('$count', style: TextStyle(color: isSelected ? Colors.white : AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsole() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 20,
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.85), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.accent, width: 2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal, color: AppColors.accent, size: 16),
                const SizedBox(width: 6),
                const Text('Console', style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                const Spacer(),
                GestureDetector(onTap: () => setState(() {_consoleMessages.clear(); _addConsoleLog('Console cleared');}), child: const Icon(Icons.clear_all, color: AppColors.accent, size: 16)),
              ],
            ),
            const Divider(color: AppColors.accent, height: 16),
            Expanded(child: ListView.builder(controller: _consoleScroll, itemCount: _consoleMessages.length, itemBuilder: (ctx, i) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(_consoleMessages[i], style: const TextStyle(color: AppColors.accent, fontSize: 10, fontFamily: 'monospace'))))),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsPanel() {
    return Positioned(
      right: 80,
      top: MediaQuery.of(context).size.height * 0.2,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.cardBackground.withOpacity(0.95), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.accent, width: 2)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [Icon(Icons.emoji_events, color: AppColors.warning, size: 16), SizedBox(width: 6), Text('Results', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary))]),
            const SizedBox(height: 12),
            ...List.generate(math.min(3, _results.length), (i) {
              final r = _results[i];
              final isTop = i == 0;
              final conf = (r['confidence'] as double) * 100;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: isTop ? AppColors.primary.withOpacity(0.2) : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isTop ? AppColors.primary : AppColors.accent, width: isTop ? 2 : 1)),
                child: Row(
                  children: [
                    Container(width: 24, height: 24, decoration: BoxDecoration(color: isTop ? AppColors.primary : AppColors.accent.withOpacity(0.3), shape: BoxShape.circle), child: Center(child: Text('${i + 1}', style: TextStyle(color: isTop ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11)))),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r['label'], style: TextStyle(fontWeight: isTop ? FontWeight.bold : FontWeight.normal, fontSize: 11, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis), Text('${conf.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.bold))])),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}