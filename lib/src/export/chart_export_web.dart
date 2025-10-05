import 'package:flutter/material.dart';
import "package:universal_html/html.dart" as html;

import 'chart_export.dart';
import 'svg_renderer.dart';

/// Platform-specific export implementation for web
Future<ExportResult> exportChartPlatform({
  required Widget chartWidget,
  required ExportConfig config,
  String? customPath,
}) async {
  switch (config.format) {
    case ExportFormat.svg:
      return await _exportToSvgWeb(chartWidget, config, customPath);
  }
}

/// Export chart as SVG for web platform using browser download API
Future<ExportResult> _exportToSvgWeb(
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

  // Generate filename
  final String filename = customPath ??
      '${config.filename ?? 'cristalyse_chart_${DateTime.now().millisecondsSinceEpoch}'}.svg';

  // Download file using browser API (WASM-compatible)
  _downloadFile(svgContent, filename, 'image/svg+xml');

  final int fileSize = svgContent.length;

  return ExportResult(
    filePath: 'browser_download:$filename',
    fileSizeBytes: fileSize,
    format: ExportFormat.svg,
    dimensions: Size(config.width, config.height),
  );
}

/// Download file using browser API (works in WASM)
void _downloadFile(String content, String filename, String mimeType) {
  final blob = html.Blob([content], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';

  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();

  html.Url.revokeObjectUrl(url);
}
