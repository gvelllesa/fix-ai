import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import '../../../../core/services/engine_ml_service.dart';
import '../../../../core/data/n55_spatial_map.dart';

class ArScanScreen extends StatefulWidget {
  final String partName;

  const ArScanScreen({Key? key, required this.partName}) : super(key: key);

  @override
  State<ArScanScreen> createState() => _ArScanScreenState();
}

class _ArScanScreenState extends State<ArScanScreen> with SingleTickerProviderStateMixin {
  ARSessionManager? arSessionManager;
  ARObjectManager? arObjectManager;
  ARAnchorManager? arAnchorManager;
  ARNode? targetNode;
  
  bool isScanning = true;
  bool isPlaneDetected = false;
  String statusMessage = "Scanning engine bay...";
  String debugStatus = "Plane Detection: Initializing...";
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    arSessionManager?.dispose();
    super.dispose();
  }

  void onARViewCreated(
      ARSessionManager arSessionManager,
      ARObjectManager arObjectManager,
      ARAnchorManager arAnchorManager,
      ARLocationManager arLocationManager) {
    this.arSessionManager = arSessionManager;
    this.arObjectManager = arObjectManager;
    this.arAnchorManager = arAnchorManager;

    this.arSessionManager!.onInitialize(
          showFeaturePoints: false,
          showPlanes: true,
          customPlaneTexturePath: "Images/triangle.png",
          showWorldOrigin: true,
          handleTaps: true,
        );
    this.arObjectManager!.onInitialize();
    this.arSessionManager!.onPlaneOrPointTap = onPlaneOrPointTapped;
    
    setState(() {
      debugStatus = "Plane Detection: Active (Tap a plane to set Engine Anchor)";
    });
    
    _simulateEngineDetection();
  }

  Future<void> _simulateEngineDetection() async {
    final engineMl = EngineMLService();
    final isDetected = await engineMl.detectEngineBay();
    
    if (isDetected && mounted) {
      setState(() {
        isScanning = false;
        statusMessage = "Target Identified! Tap the engine plane.";
      });
    }
  }

  Future<void> onPlaneOrPointTapped(List<ARHitTestResult> hitTestResults) async {
    if (targetNode != null) return; // already placed
    
    final singleHitTestResult = hitTestResults.firstWhere((hitTestResult) => hitTestResult.type == ARHitTestResultType.plane);
    if (singleHitTestResult != null) {
      setState(() {
        debugStatus = "Engine Anchor Set at Plane!";
        statusMessage = "Highlighting 3D Part...";
      });
      
      var newAnchor = ARPlaneAnchor(transformation: singleHitTestResult.worldTransform);
      bool? didAddAnchor = await arAnchorManager?.addAnchor(newAnchor);
      if (didAddAnchor == true) {
        _placeTargetNode(newAnchor);
      }
    }
  }

  Future<void> _placeTargetNode(ARPlaneAnchor anchor) async {
    final offset = N55SpatialMap.getOffsetForPart(widget.partName);
    
    final webNode = ARNode(
      type: NodeType.webGLB,
      uri: "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Box/glTF-Binary/Box.glb",
      scale: vector.Vector3(0.05, 0.05, 0.05), // make it smaller to fit engine bays better
      position: offset, // Relative to the anchor
    );

    bool? didAdd = await arObjectManager?.addNode(webNode, planeAnchor: anchor);
    if (didAdd == true) {
      targetNode = webNode;
      setState(() {
        statusMessage = "Part Highlighted!";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ARView(
            onARViewCreated: onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          ),
          
          // Floating Close Button
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
          
          // Target Information overlay
          Positioned(
            top: 50,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Looking for: ${widget.partName}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    debugStatus,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Offset: ${N55SpatialMap.getOffsetForPart(widget.partName).toString()}",
                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),

          // Scanning Animation Overlay
          if (isScanning)
            Center(
              child: ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.greenAccent, width: 4),
                    color: Colors.greenAccent.withOpacity(0.2),
                  ),
                  child: const Center(
                    child: Icon(Icons.search, color: Colors.greenAccent, size: 50),
                  ),
                ),
              ),
            ),

          // Status Message
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: isScanning ? Colors.greenAccent : Colors.blueAccent),
                ),
                child: Text(
                  statusMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
