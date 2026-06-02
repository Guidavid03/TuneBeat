import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// UI state switch panel utilized for peripheral hardware controllers
class ToggleButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const ToggleButton({
    super.key,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,

        // --- BUTTON ARCHITECTURE DESIGN ---
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 32, color: AppColors.textDark),
      ),
    );
  }
}
