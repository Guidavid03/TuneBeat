import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tunebeat/core/constants/app_colors.dart';

/// System permissions handler
class PermissionsHelper {

  // --- PUBLIC PERMISSION REQUESTS ---

  /// Requests microphone access -> returns true if granted
  static Future<bool> requestMicrophonePermission(BuildContext context) async {
    var status = await Permission.microphone.request();
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied && context.mounted) {
      _showSettingsDialog(context, 'Microphone');
    }
    return false;
  }

  /// Requests camera access -> returns true if granted
  static Future<bool> requestCameraPermission(BuildContext context) async {
    var status = await Permission.camera.request();
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied && context.mounted) {
      _showSettingsDialog(context, 'Camera');
    }
    return false;
  }

  // --- PRIVATE UI COMPONENTS ---

  /// Shows a dialog prompting the user to enable permissions in the system settings
  static void _showSettingsDialog(BuildContext context, String permissionName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        surfaceTintColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Permission Required',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'TuneBeat needs access to the $permissionName to function properly. Please enable the permission in your device settings.',
          style: const TextStyle(color: AppColors.textDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textLight),
            ),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text(
              'Open Settings',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
