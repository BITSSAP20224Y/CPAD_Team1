import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';

class HandTracker {
  Interpreter? _interpreter;
  List<List<List<double>>>? _lastDetectedLandmarks;

  List<List<List<double>>>? get lastDetectedLandmarks => _lastDetectedLandmarks;

  Future<void> loadModel() async {
    try {
      String modelPath = 'assets/models/hand_landmarks_detector.tflite';

      _interpreter = await Interpreter.fromAsset(modelPath);
      print("✅ Hand Landmarker model loaded!");
    } catch (e) {
      print("❌ Failed to load model: $e");
      _interpreter = null;
    }
  }

  // Getter returns the nullable interpreter
  Interpreter? get interpreter => _interpreter;

  Future<Map<bool, List<List<List<double>>>>> detectHand(Uint8List imageData) async {
    // Check if interpreter is loaded *before* trying to use it
    if (_interpreter == null) {
      print("❌ Interpreter not loaded. Cannot detect hand.");
      return {};
    }

    try {
      // Decode image
      img.Image? image = img.decodeImage(imageData);
      if (image == null) {
        print("⚠️ Failed to decode image.");
        return {};
      }

      // --- Model Input Preparation ---
      // Ensure the input size matches your specific model.
      // Common sizes are 224x224, 256x256, 192x192 etc.
      int modelInputWidth = 224;
      int modelInputHeight = 224;

      // Resize image to model's expected input size
      img.Image resizedImage = img.copyResize(image, width: modelInputWidth, height: modelInputHeight);

      // Convert image to Float32 format for TensorFlow Lite input
      var input = _imageToByteListFloat32(resizedImage, modelInputWidth, modelInputHeight);

       var outputs = {
         // Landmarks (Float32, shape [1, 63])
         0: [List.filled(63, 0.0)],
         1: List.filled(1, 0.0).reshape([1, 1]), // Score output
         2: List.filled(1, 0.0).reshape([1, 1]), // Handedness output
         3: [List.filled(63, 0.0)],
       };

      // Run inference
      _interpreter!.runForMultipleInputs([input], outputs);

      // --- Process Output ---
      var landmarkData = outputs[0] as List<List<double>>; 
      var isHandPresent = outputs[1]![0][0]; 
      // Check if output data is valid
      if (landmarkData.isEmpty || landmarkData[0].length != 63) {
          print("⚠️ Invalid landmark output data received from model.");
          return {};
      }

      // Reshape the flat [1, 63] list into [1, 21, 3]
      List<List<List<double>>> reshapedLandmarks = [[]]; // Initialize structure
      List<double> flatLandmarks = landmarkData[0];

      for (int i = 0; i < 21; i++) {
        int baseIndex = i * 3;
        if (baseIndex + 2 < flatLandmarks.length) {
          reshapedLandmarks[0].add([
            flatLandmarks[baseIndex],     // x
            flatLandmarks[baseIndex + 1], // y
            flatLandmarks[baseIndex + 2]  // z (may not be used for 2D drawing)
          ]);
        } else {
           print("⚠️ Error reshaping landmark data: index out of bounds.");
           return {}; // Invalid data
        }
      }

      _lastDetectedLandmarks = reshapedLandmarks; // Store the detected landmarks

      return {
        isHandPresent > 0.5: reshapedLandmarks // Assuming isHandPresent is a float score
      };

    } catch (e, stackTrace) {
      print("⚠️ Error running hand detection: $e");
      print("Stack trace: $stackTrace"); 
      return {};
    }
  }

  // Corrected: Uses Pixel object properties
  Uint8List _imageToByteListFloat32(img.Image image, int width, int height) {
    var convertedBytes = Float32List(1 * width * height * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Get the pixel object
        var pixel = image.getPixel(x, y);
        buffer[pixelIndex++] = pixel.r / 255.0; // Normalize R
        buffer[pixelIndex++] = pixel.g / 255.0; // Normalize G
        buffer[pixelIndex++] = pixel.b / 255.0; // Normalize B
      }
    }
    // Return the underlying byte buffer
    return convertedBytes.buffer.asUint8List();
  }

  // Call this method when the HandTracker is no longer needed, e.g., in dispose()
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    print("HandTracker interpreter closed.");
  }
}