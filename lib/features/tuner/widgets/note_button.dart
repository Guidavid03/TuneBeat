import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Material grid tab button for targeting reference string note values
class NoteButton extends StatelessWidget {
  final String note;
  final bool isActive;
  final VoidCallback onTap;

  const NoteButton({
    super.key,
    required this.note,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: isActive ? AppColors.primary : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,

        // --- TEXT COMPONENT STYLING ---
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : AppColors.textDark,
            fontFamily: 'Roboto',
          ),
          child: Text(note),
        ),
      ),
    );
  }
}
