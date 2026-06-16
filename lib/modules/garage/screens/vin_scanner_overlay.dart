import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';

class VinScannerOverlay extends StatefulWidget {
  const VinScannerOverlay({Key? key}) : super(key: key);

  @override
  State<VinScannerOverlay> createState() => _VinScannerOverlayState();
}

class _VinScannerOverlayState extends State<VinScannerOverlay> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String _statusMessage = "Point camera at VIN code. Avoid glare.";
  
  late AnimationController _borderPulseController;

  @override
  void initState() {
    super.initState();
    _borderPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception("No cameras available");
      
      _cameraController = CameraController(
        cameras.firstWhere((cam) => cam.lensDirection == CameraLensDirection.back, orElse: () => cameras.first),
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });

      _cameraController!.startImageStream(_processCameraFrame);
    } catch (e) {
      setState(() {
        _statusMessage = "Camera Error: \$e";
      });
    }
  }

  Future<void> _processCameraFrame(CameraImage image) async {
    if (_isProcessing || !_isCameraInitialized) return;
    _isProcessing = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final recognizedText = await _textRecognizer.processImage(inputImage);
      
      // Regex strictly matching 17-digit VIN pattern (no I, O, Q)
      final regex = RegExp(r'[A-HJ-NPR-Z0-9]{17}');
      
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final text = line.text.replaceAll(RegExp(r'\\s+'), '').toUpperCase(); // strip spaces
          if (regex.hasMatch(text)) {
            final match = regex.firstMatch(text)!.group(0)!;
            _onVinDetected(match);
            return; // Stop processing once found
          }
        }
      }
    } catch (e) {
      debugPrint("OCR Error: \$e");
    } finally {
      if (mounted) _isProcessing = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;
    
    final InputImageRotation? rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || (Platform.isAndroid && format != InputImageFormat.nv21) || (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    
    if (image.planes.isEmpty) return null;

    return InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  void _onVinDetected(String vin) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _cameraController?.stopImageStream();
    
    setState(() {
      _statusMessage = "VIN Captured: \$vin";
    });
    
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) Navigator.pop(context, vin);
    });
  }

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _statusMessage = "Analyzing Image...");
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      
      final regex = RegExp(r'[A-HJ-NPR-Z0-9]{17}');
      bool found = false;
      
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final text = line.text.replaceAll(RegExp(r'\\s+'), '').toUpperCase();
          if (regex.hasMatch(text)) {
            final match = regex.firstMatch(text)!.group(0)!;
            found = true;
            _onVinDetected(match);
            break;
          }
        }
        if (found) break;
      }
      
      if (!found && mounted) {
        setState(() => _statusMessage = "No valid 17-digit VIN found in image.");
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
    _borderPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isCameraInitialized)
            CameraPreview(_cameraController!)
          else
            const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue)),
            
          // Dark Overlay with Cutout
          ColorFiltered(
            colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcOut),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(color: Colors.black, backgroundBlendMode: BlendMode.dstOut),
                ),
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    height: 100, // standard VIN barcode/text height
                    decoration: BoxDecoration(
                      color: Colors.white, // cut out
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Focus Frame
          Center(
            child: AnimatedBuilder(
              animation: _borderPulseController,
              builder: (context, child) {
                return Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  height: 100,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppTheme.primaryBlue.withOpacity(0.5 + (_borderPulseController.value * 0.5)),
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                );
              },
            ),
          ),
          
          // Instructions Text
          Positioned(
            top: MediaQuery.of(context).size.height * 0.25,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

          // Top Controls
          Positioned(
            top: 50,
            right: 20,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          
          // Bottom Controls
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surfaceObsidian,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: _pickImageFromGallery,
                icon: const Icon(Icons.photo_library),
                label: const Text("Upload from Gallery"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
