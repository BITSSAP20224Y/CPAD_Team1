import 'package:flutter/material.dart';
import 'dart:ui' as ui; 

class LandmarkPainter extends CustomPainter {
  final List<List<List<double>>> landmarks; 
  final Size imageSize; 
  final bool isFrontCamera; 

  LandmarkPainter({required this.landmarks, required this.imageSize, this.isFrontCamera = false});

  
  final List<List<int>> landmarkConnections = [
    [0, 1], [1, 2], [2, 3], [3, 4],         
    [0, 5], [5, 6], [6, 7], [7, 8],         
    [5, 9], [9, 10], [10, 11], [11, 12],    
    [9, 13], [13, 14], [14, 15], [15, 16],   
    [13, 17], [17, 18], [18, 19], [19, 20],  
    [0, 17]                                 
  ];

  @override
  void paint(Canvas canvas, Size size) {
    
    if (landmarks.isEmpty || landmarks[0].isEmpty || imageSize.width <= 0 || imageSize.height <= 0) {
        
        return;
    }

    final Paint pointPaint = Paint()
      ..color = Colors.lightGreenAccent 
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8.0; 

    final Paint linePaint = Paint()
      ..color = Colors.cyanAccent 
      ..strokeWidth = 3.0; 

    
    List<List<double>> handLandmarks = landmarks[0];

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    
    List<Offset> scaledPoints = [];
    for (int i = 0; i < handLandmarks.length; i++) {

      double lx = handLandmarks[i][0]; 
      double ly = handLandmarks[i][1]; 

      
      double canvasX = lx * scaleX;
      double canvasY = ly * scaleY;

       
      if (isFrontCamera) {
           canvasX = size.width - canvasX;
      }

      scaledPoints.add(Offset(canvasX, canvasY));
    }

    
    for (var connection in landmarkConnections) {
      if (connection[0] < scaledPoints.length && connection[1] < scaledPoints.length) {
        canvas.drawLine(scaledPoints[connection[0]], scaledPoints[connection[1]], linePaint);
      }
    }

    
    
    canvas.drawPoints(ui.PointMode.points, scaledPoints, pointPaint);
  }

  @override
  bool shouldRepaint(covariant LandmarkPainter oldDelegate) {
    
    return oldDelegate.landmarks != landmarks || oldDelegate.imageSize != imageSize || oldDelegate.isFrontCamera != isFrontCamera;
  }
}