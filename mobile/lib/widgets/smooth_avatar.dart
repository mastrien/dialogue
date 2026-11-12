import 'dart:io';
import 'package:flutter/material.dart';
import '../rust_bridge.dart';

Color parseHexColor(String hex) {
  final clean = hex.replaceFirst('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return const Color(0xFF6366F1);
}

class SmoothAvatar extends StatelessWidget {
  final String name;
  final String? avatarPath;
  final String colorHex;
  final double radius;

  const SmoothAvatar({
    super.key,
    required this.name,
    this.avatarPath,
    this.colorHex = '#6366F1',
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final fullPath = RustBridge.resolveMediaFile(avatarPath);
    if (fullPath != null && File(fullPath).existsSync()) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(File(fullPath)),
      );
    }

    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
    final initials = parts.map((p) => p[0].toUpperCase()).join();

    return CircleAvatar(
      radius: radius,
      backgroundColor: parseHexColor(colorHex),
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.72,
        ),
      ),
    );
  }
}
