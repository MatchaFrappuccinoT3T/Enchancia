import 'dart:io';

import 'package:flutter/material.dart';

/// Full-screen, pinch-to-zoom viewer for a sent image (requirement 四.2).
class ImageViewerScreen extends StatelessWidget {
  final String path;
  final String heroTag;

  const ImageViewerScreen({
    super.key,
    required this.path,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Center(
          child: Hero(
            tag: heroTag,
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.file(File(path)),
            ),
          ),
        ),
      ),
    );
  }
}
