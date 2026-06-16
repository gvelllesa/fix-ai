import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class TypingIndicator extends StatelessWidget {
  const TypingIndicator({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'AI is typing',
              style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7), fontSize: 14),
            ),
            const SizedBox(width: 8),
            Row(
              children: List.generate(3, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    shape: BoxShape.circle,
                  ),
                ).animate(
                  onPlay: (controller) => controller.repeat(),
                ).scaleY(
                  begin: 0.5,
                  end: 1.5,
                  duration: const Duration(milliseconds: 600),
                  delay: Duration(milliseconds: index * 200),
                  curve: Curves.easeInOut,
                ).then().scaleY(
                  begin: 1.5,
                  end: 0.5,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOut,
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
