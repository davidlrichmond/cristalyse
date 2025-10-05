import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'chart_export.dart';
import 'svg_renderer.dart';

/// Platform-specific export implementation for mobile/desktop
Future<ExportResult> exportChartPlatform({
  required Widget chartWidget,
  required ExportConfig config,
  String? customPath,
}) async {
  switch (config.format) {
    case ExportFormat.svg:
      return await _exportToSvg(chartWidget, config, customPath);
  }
}

/// Export chart as SVG for mobile/desktop platforms
Future<ExportResult> _exportToSvg(
  Widget chartWidget,
  ExportConfig config,
  String? customPath,
) async {
  // Use shared SVG renderer with Wilkinson Extended labeling
  final renderer = SvgRenderer(
    width: config.width,
    height: config.height,
    backgroundColor: config.backgroundColor,
  );

  // Generate SVG content
  final String svgContent = renderer.generateSvg(chartWidget);

  // Save to file
  final String filePath = customPath ?? await _getExportPath(config, 'svg');
  final File file = File(filePath);
  await file.writeAsString(svgContent);

  final int fileSize = svgContent.length;

  return ExportResult(
    filePath: filePath,
    fileSizeBytes: fileSize,
    format: ExportFormat.svg,
    dimensions: Size(config.width, config.height),
  );
}

/// Get the default export path using path_provider
Future<String> _getExportPath(
  ExportConfig config,
  String extension,
) async {
  final Directory directory = await getApplicationDocumentsDirectory();
  if (directory.path.isEmpty) {
    throw const ChartExportException('Could not access documents directory');
  }

  final String filename = config.filename ??
      'cristalyse_chart_${DateTime.now().millisecondsSinceEpoch}';

  return '${directory.path}/$filename.$extension';
}
