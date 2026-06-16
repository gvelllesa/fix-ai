import 'package:flutter/material.dart';

class MediaButtons extends StatelessWidget {
  final VoidCallback onCameraPressed;
  final VoidCallback onMicrophonePressed;

  const MediaButtons({
    Key? key,
    required this.onCameraPressed,
    required this.onMicrophonePressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.camera_alt_outlined),
          color: const Color(0xFF6F6F6F), // secondaryText
          tooltip: 'Take Photo',
          onPressed: onCameraPressed,
        ),
        IconButton(
          icon: const Icon(Icons.mic_none),
          color: const Color(0xFF6F6F6F),
          tooltip: 'Record Audio',
          onPressed: onMicrophonePressed,
        ),
      ],
    );
  }
}
