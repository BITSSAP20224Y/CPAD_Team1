import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:math' as math;
import 'hand_tracker.dart';
import 'package:image/image.dart' as img;

class CameraScreen extends StatefulWidget {
  final HandTracker handTracker;

  const CameraScreen({super.key, required this.handTracker});

  @override
  CameraScreenState createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  String _liveDetectedGesture = "Initializing..."; // For live feedback
  List<CameraDescription>? _cameras;
  int _frameCount = 0;

  // --- Game State Variables ---
  String _playerChoice = "";
  String _computerChoice = "";
  String _gameResult = "";
  int _playerScore = 0;
  int _computerScore = 0;
  String _gameStatusMessage = "Press 'Play' to start"; // General status/instruction message

  bool _isRoundInProgress = false;
  Timer? _countdownTimer;
  int _countdownValue = 3;

  final List<String> _rpsChoices = ["Rock", "Paper", "Scissor"];
  final math.Random _random = math.Random();
  // --- End Game State Variables ---


  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _controller?.stopImageStream().catchError((e) {
      debugPrint("Error stopping image stream: $e");
    });
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint("❌ No cameras available");
        if (!mounted) return;
        setState(() {
          _liveDetectedGesture = "Error: No camera found";
          _gameStatusMessage = "Camera Error";
        });
        return;
      }

      _controller = CameraController(
        _cameras![0],
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        _liveDetectedGesture = "Detecting...";
      });

      _controller!.startImageStream(_processCameraImage);

    } on CameraException catch (e) {
      debugPrint("❌ Error initializing camera: $e");
      if (!mounted) return;
      setState(() {
        _liveDetectedGesture = "Error: Camera access denied or failed";
        _gameStatusMessage = "Camera Error: ${e.description}";
      });
    } catch (e) {
      debugPrint("❌ Unexpected error initializing camera: $e");
      if (!mounted) return;
       setState(() {
        _liveDetectedGesture = "Error: Failed to initialize camera";
        _gameStatusMessage = "Camera Initialization Failed";
      });
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting || !mounted || widget.handTracker.interpreter == null) {
      return;
    }

    _frameCount++;
    if (_frameCount % 5 != 0) { // Process every 5th frame
      return;
    }
    _isDetecting = true;

    try {
      Uint8List? imageData = _convertCameraImageToUint8List(image);

      try {
        Map<bool, List<List<List<double>>>> handDetectionResult =
            await widget.handTracker.detectHand(imageData);

        String gesture;
        if (handDetectionResult.isEmpty || handDetectionResult[true] == null || handDetectionResult[true]!.isEmpty) {
          gesture = "No hand detected";
        } else {
          List<List<List<double>>> landmarks = handDetectionResult[true]!;
          gesture = _classifyGesture(landmarks);
        }

        if (mounted) {
          setState(() {
            _liveDetectedGesture = gesture;
          });
        }
      } catch (e) {
        debugPrint("⚠️ Error in hand detection/classification: $e");
        if (mounted) {
          setState(() {
            _liveDetectedGesture = "Error detecting";
          });
        }
      } finally {
        imageData = null; // Help GC
      }
    } catch (e) {
      debugPrint("⚠️ Error processing camera image: $e");
       if (mounted) {
          setState(() {
            _liveDetectedGesture = "Image processing error";
          });
        }
    } finally {
       _isDetecting = false;
    }
  }

  Uint8List _convertCameraImageToUint8List(CameraImage image) {
    img.Image imgFrame = img.Image(width: image.width, height: image.height);
    final int yRowStride = image.planes[0].bytesPerRow;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final int uvIndex = uvRowStride * (y ~/ 2) + (x ~/ 2) * uvPixelStride;
        final int yIndex = yRowStride * y + x;
        final int yValue = image.planes[0].bytes[yIndex];
        final int uValue = image.planes[1].bytes[uvIndex];
        final int vValue = image.planes[2].bytes[uvIndex];
        final int r = (yValue + 1.402 * (vValue - 128)).clamp(0, 255).toInt();
        final int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).clamp(0, 255).toInt();
        final int b = (yValue + 1.772 * (uValue - 128)).clamp(0, 255).toInt();
        imgFrame.setPixelRgb(x, y, r, g, b); // Use setPixelRgb for efficiency
      }
    }
    return Uint8List.fromList(img.encodePng(imgFrame));
  }

  double _distance(List<double> p1, List<double> p2) {
    if (p1.length < 2 || p2.length < 2) return 0.0;
    final double dx = p1[0] - p2[0];
    final double dy = p1[1] - p2[1];
    return math.sqrt(dx * dx + dy * dy);
  }

  String _classifyGesture(List<List<List<double>>> landmarks) {
    if (landmarks.isEmpty || landmarks[0].isEmpty || landmarks[0].length < 21) {
      return "No hand present";
    }
    List<List<double>> handLandmarks = landmarks[0];

    const int wrist = 0, thumbTip = 4, indexTip = 8, middleTip = 12, ringTip = 16, pinkyTip = 20;
    const int indexMcp = 5, middleMcp = 9, ringMcp = 13, pinkyMcp = 17;

    double refDistance = _distance(handLandmarks[wrist], handLandmarks[middleMcp]);
    if (refDistance < 1e-6) {
      debugPrint("⚠️ Reference distance is near zero, cannot classify.");
      return "Detection Error";
    }

    double indexRatio = _distance(handLandmarks[indexMcp], handLandmarks[indexTip]) / refDistance;
    double middleRatio = _distance(handLandmarks[middleMcp], handLandmarks[middleTip]) / refDistance;
    double ringRatio = _distance(handLandmarks[ringMcp], handLandmarks[ringTip]) / refDistance;
    double pinkyRatio = _distance(handLandmarks[pinkyMcp], handLandmarks[pinkyTip]) / refDistance;

    const double extensionRatioThreshold = 0.6; // Needs Tuning!
    bool indexExtended = indexRatio > extensionRatioThreshold;
    bool middleExtended = middleRatio > extensionRatioThreshold;
    bool ringExtended = ringRatio > extensionRatioThreshold;
    bool pinkyExtended = pinkyRatio > extensionRatioThreshold;

    double thumbIndexMcpDist = _distance(handLandmarks[thumbTip], handLandmarks[indexMcp]);
    double thumbCurlRatio = thumbIndexMcpDist / refDistance;
    const double thumbCurlRatioThreshold = 0.6; // Needs Tuning!
    bool thumbCurled = thumbCurlRatio < thumbCurlRatioThreshold;

    int extendedFingers = (indexExtended ? 1 : 0) + (middleExtended ? 1 : 0) + (ringExtended ? 1 : 0) + (pinkyExtended ? 1 : 0);

    if (extendedFingers >= 4) return "Paper";
    if (extendedFingers == 0 && thumbCurled) return "Rock";
    if (indexExtended && middleExtended && !ringExtended && !pinkyExtended) return "Scissor";
    if (extendedFingers == 0 && !thumbCurled) return "Rock"; // Potentially Rock
    return "Detected";
  }

  // --- Game Logic Implementation ---
  void _startGameRound() {
    if (_isRoundInProgress || !_isCameraInitialized) return;

    setState(() {
      _playerChoice = "";
      _computerChoice = "";
      _gameResult = "";
      _gameStatusMessage = "Ready?";
    });

    Future.delayed(const Duration(milliseconds: 1500), () { // "Ready?" display time
      if (!mounted) return;
      setState(() {
        _isRoundInProgress = true;
        _countdownValue = 3;
        _gameStatusMessage = "$_countdownValue...";
      });

      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_countdownValue > 1) {
            _countdownValue--;
            _gameStatusMessage = "$_countdownValue...";
          } else if (_countdownValue == 1) {
            _countdownValue--;
            _gameStatusMessage = "SHOOT!";
            _capturePlayerMove(); // Capture gesture at "SHOOT!"
          } else {
            timer.cancel();
            _determineOutcome();
            _isRoundInProgress = false;
            // _gameStatusMessage is updated in _determineOutcome or if player move was invalid
          }
        });
      });
    });
  }

  void _capturePlayerMove() {
    // Use the currently live detected gesture
    if (_rpsChoices.contains(_liveDetectedGesture)) {
      _playerChoice = _liveDetectedGesture;
    } else {
      _playerChoice = "Invalid"; // Player failed to show a valid gesture
    }
  }

  void _makeComputerChoice() {
    _computerChoice = _rpsChoices[_random.nextInt(_rpsChoices.length)];
  }

  void _determineOutcome() {
    _makeComputerChoice(); // Computer makes its choice now

    if (_playerChoice == "Invalid" || _playerChoice.isEmpty) {
      _gameResult = "Your move was unclear!";
      // Computer wins by default if player move is invalid
      _computerScore++;
      setState(() {
         _gameStatusMessage = "Try Again?";
      });
      return;
    }

    if (_playerChoice == _computerChoice) {
      _gameResult = "It's a Draw!";
    } else if ((_playerChoice == "Rock" && _computerChoice == "Scissor") ||
               (_playerChoice == "Paper" && _computerChoice == "Rock") ||
               (_playerChoice == "Scissor" && _computerChoice == "Paper")) {
      _gameResult = "You Win this round!";
      _playerScore++;
    } else {
      _gameResult = "Computer Wins this round!";
      _computerScore++;
    }
    setState(() {
      _gameStatusMessage = "Play Again?";
    });
  }
  // --- End Game Logic ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rock Paper Scissor')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Preview
          _isCameraInitialized && _controller != null && _controller!.value.isInitialized
              ? CameraPreview(_controller!)
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 10),
                      Text(_gameStatusMessage == "Press 'Play' to start" && !_isCameraInitialized ? "Initializing Camera..." : _gameStatusMessage),
                    ],
                  ),
                ),

          // Game Info Overlay
          Positioned(
            top: 20.0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12.0),
              color: Colors.black.withOpacity(0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isRoundInProgress && _countdownValue > 0 ? "$_countdownValue..." :
                    _isRoundInProgress && _gameStatusMessage == "SHOOT!" ? "SHOOT!" : _gameStatusMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 28.0, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text("Player: $_playerScore", style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text("VS", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text("CPU: $_computerScore", style: const TextStyle(color: Colors.orangeAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  // Show choices and result only after the round is over and choices are made
                  if (!_isRoundInProgress && _playerChoice.isNotEmpty && _computerChoice.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text("Your move: $_playerChoice", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: _playerChoice == "Invalid" ? FontWeight.normal : FontWeight.bold)),
                    Text("CPU's move: $_computerChoice", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_gameResult, style: const TextStyle(color: Colors.yellowAccent, fontSize: 22, fontWeight: FontWeight.bold)),
                  ]
                ],
              ),
            ),
          ),

          // Live Detected Gesture Text (feedback for player)
          Positioned(
            bottom: 100.0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              color: Colors.black.withOpacity(0.5),
              child: Text(
                "Current Detection: $_liveDetectedGesture",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18.0,
                ),
              ),
            ),
          ),

          // Play Button
          if (_isCameraInitialized) // Only show play button if camera is ready
            Positioned(
              bottom: 20.0,
              left: 20.0,
              right: 20.0,
              child: ElevatedButton(
                onPressed: _isRoundInProgress ? null : _startGameRound,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRoundInProgress ? Colors.grey[700] : Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 22.0, fontWeight: FontWeight.bold, color: Colors.white)
                ),
                child: Text(
                  _isRoundInProgress ? "Playing..." : "PLAY ROUND",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}