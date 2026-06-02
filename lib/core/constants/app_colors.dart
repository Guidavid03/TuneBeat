import 'package:flutter/material.dart';

/// Global color palette
class AppColors {

  // --- BACKGROUNDS AND SURFACES ---
  static const Color background = Color(0xFFF7F3F9);  /// main application background
  static const Color card = Color(0xFFFFFFFF);  /// elevated surfaces like menus

  // --- PRIMARY AND ACCENT COLORS ---
  static const Color primary = Color(0xFF629388);
  static const Color secondary = Color(0xFF8AB789);

  // --- TEXT COLORS ---
  static const Color textDark = Color(0xFF404040);  /// primary text color for titles, active notes and general UI text
  static const Color textLight = Color(0x80404040); /// secondary text color for subtitles and unselected tabs

  // --- STATE COLORS ---
  static const Color inactive = Color(0xFFEAECEB);  /// used for disabled states, like unselected switches and toggle buttons
}
