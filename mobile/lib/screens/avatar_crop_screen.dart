import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../i18n.dart';

class AvatarCropScreen extends StatefulWidget {
  final String lang;
  final String imagePath;

  const AvatarCropScreen({
    super.key,
    required this.lang,
    required this.imagePath,
  });

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  static const double _cropSize = 280.0;
  final GlobalKey _cropKey = GlobalKey();
  final TransformationController _controller = TransformationController();
  double _zoom = 1.0;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setZoom(double scale) {
    final current = _controller.value;
    final currentScale = current.getMaxScaleOnAxis();
    if (currentScale <= 0) return;
    final ratio = scale / currentScale;
    const center = _cropSize / 2;
    final next = current.clone()
      ..translateByDouble(center, center, 0, 1)
      ..scaleByDouble(ratio, ratio, 1, 1)
      ..translateByDouble(-center, -center, 0, 1);
    _controller.value = next;
    setState(() => _zoom = scale);
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary =
          _cropKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final outFile = File(
        '${Directory.systemTemp.path}/dialogue_crop_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await outFile.writeAsBytes(bytes, flush: true);
      if (mounted) Navigator.pop(context, outFile.path);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(tr(widget.lang, 'adjustPhoto')),
        actions: [
          IconButton(
            onPressed: _saving ? null : _confirm,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
          ),
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: SizedBox(
              width: _cropSize,
              height: _cropSize,
              child: Stack(
                children: [
                  RepaintBoundary(
                    key: _cropKey,
                    child: ClipRect(
                      child: SizedBox(
                        width: _cropSize,
                        height: _cropSize,
                        child: InteractiveViewer(
                          transformationController: _controller,
                          minScale: 1.0,
                          maxScale: 5.0,
                          boundaryMargin: const EdgeInsets.all(200),
                          onInteractionUpdate: (_) {
                            final s = _controller.value
                                .getMaxScaleOnAxis()
                                .clamp(1.0, 5.0);
                            if ((s - _zoom).abs() > 0.01) {
                              setState(() => _zoom = s);
                            }
                          },
                          child: Image.file(
                            File(widget.imagePath),
                            width: _cropSize,
                            height: _cropSize,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      size: const Size(_cropSize, _cropSize),
                      painter: _CircleCropOverlayPainter(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                const Icon(Icons.zoom_out, color: Colors.white70, size: 20),
                Expanded(
                  child: Slider(
                    value: _zoom.clamp(1.0, 5.0),
                    min: 1.0,
                    max: 5.0,
                    onChanged: _setZoom,
                  ),
                ),
                const Icon(Icons.zoom_in, color: Colors.white70, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleCropOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final overlay = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
