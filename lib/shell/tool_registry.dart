import 'package:flutter/material.dart';

import '../tools/edge/edge_screen.dart';
import '../tools/face_names/face_names_screen.dart';
import '../tools/region_zoom/region_zoom_screen.dart';

/// One entry in the tool picker: id, label, icon, route.
class ToolEntry {
  const ToolEntry({
    required this.id,
    required this.label,
    required this.icon,
    required this.route,
  });
  final String id;
  final String label;
  final IconData icon;
  final Widget Function() route;
}

/// Registry of all tools; drives picker and deep links.
class ToolRegistry {
  static const String edge = 'edge';
  static const String regionZoom = 'region_zoom';
  static const String faceNames = 'face_names';

  static List<ToolEntry> get all => [
        ToolEntry(
          id: edge,
          label: 'Edge Highlight',
          icon: Icons.contrast,
          route: _edgeRoute,
        ),
        ToolEntry(
          id: regionZoom,
          label: 'Region Zoom',
          icon: Icons.zoom_in,
          route: _regionZoomRoute,
        ),
        ToolEntry(
          id: faceNames,
          label: 'Face & Names',
          icon: Icons.face,
          route: _faceNamesRoute,
        ),
      ];

  static Widget _edgeRoute() => const EdgeScreen();
  static Widget _regionZoomRoute() => const RegionZoomScreen();
  static Widget _faceNamesRoute() => const FaceNamesScreen();

  static Widget screenForId(String id) {
    for (final e in all) {
      if (e.id == id) return e.route();
    }
    return all.first.route();
  }
}
