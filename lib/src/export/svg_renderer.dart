import 'package:flutter/material.dart';

import '../core/geometry.dart';
import '../core/scale.dart';
import '../themes/chart_theme.dart';
import '../widgets/animated_chart_widget.dart';

/// Shared SVG renderer using public Scale classes and Wilkinson Extended labeling
class SvgRenderer {
  final double width;
  final double height;
  final Color? backgroundColor;

  SvgRenderer({
    required this.width,
    required this.height,
    this.backgroundColor,
  });

  String generateSvg(Widget chartWidget) {
    final StringBuffer buffer = StringBuffer();

    // SVG header
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
      '<svg width="$width" height="$height" '
      'xmlns="http://www.w3.org/2000/svg" '
      'xmlns:xlink="http://www.w3.org/1999/xlink">',
    );

    // Background
    if (backgroundColor != null) {
      final color = _colorToHex(backgroundColor!);
      buffer.writeln('  <rect width="$width" height="$height" fill="$color"/>');
    }

    // Extract chart data and render to SVG
    _renderChartToSvg(chartWidget, buffer);

    // SVG footer
    buffer.writeln('</svg>');

    return buffer.toString();
  }

  void _renderChartToSvg(Widget chartWidget, StringBuffer buffer) {
    // Extract chart data from the widget tree
    final chartData = _extractChartData(chartWidget);
    if (chartData == null) {
      // Fallback for unsupported chart types
      buffer.writeln(
        '  <text x="50%" y="50%" text-anchor="middle" '
        'dominant-baseline="middle" font-family="Arial, sans-serif" '
        'font-size="16" fill="#666">',
      );
      buffer.writeln('    Chart SVG Export');
      buffer.writeln('  </text>');
      return;
    }

    // Calculate plot area
    final padding = chartData.theme.padding;
    final plotArea = Rect.fromLTWH(
      padding.left,
      padding.top,
      width - padding.horizontal,
      height - padding.vertical,
    );

    // Setup scales using public Scale classes
    final xScale = _setupXScale(chartData, plotArea.width);
    final yScale = _setupYScale(chartData, plotArea.height);
    final y2Scale = _setupY2Scale(chartData, plotArea.height);
    final colorScale = _setupColorScale(chartData);
    final sizeScale = _setupSizeScale(chartData);

    // Render chart elements
    _renderBackground(buffer, plotArea, chartData.theme);
    _renderGrid(buffer, plotArea, xScale, yScale, chartData.theme);
    _renderGeometries(
      buffer,
      plotArea,
      chartData,
      xScale,
      yScale,
      y2Scale,
      colorScale,
      sizeScale,
    );
    _renderAxes(buffer, plotArea, xScale, yScale, y2Scale, chartData.theme);
  }

  _ChartData? _extractChartData(Widget chartWidget) {
    // Extract data from AnimatedCristalyseChartWidget
    if (chartWidget is AnimatedCristalyseChartWidget) {
      return _ChartData(
        data: chartWidget.data,
        xColumn: chartWidget.xColumn,
        yColumn: chartWidget.yColumn,
        y2Column: chartWidget.y2Column,
        colorColumn: chartWidget.colorColumn,
        sizeColumn: chartWidget.sizeColumn,
        geometries: chartWidget.geometries,
        theme: chartWidget.theme,
      );
    }
    return null;
  }

  Scale _setupXScale(_ChartData chartData, double plotWidth) {
    if (chartData.xColumn == null) {
      final scale = LinearScale();
      scale.domain = [0, 1];
      scale.range = [0, plotWidth];
      return scale;
    }

    final xValues = chartData.data
        .map((d) => d[chartData.xColumn])
        .where((v) => v != null)
        .toList();

    if (xValues.isEmpty) {
      final scale = LinearScale();
      scale.domain = [0, 1];
      scale.range = [0, plotWidth];
      return scale;
    }

    // Check if data is numeric or categorical
    final firstValue = xValues.first;
    if (firstValue is num) {
      final numValues = xValues.map((v) => (v as num).toDouble()).toList();
      final scale = LinearScale();
      scale.range = [0, plotWidth];
      scale.setBounds(numValues, null, chartData.geometries);
      return scale;
    } else {
      final categories = xValues.map((v) => v.toString()).toSet().toList();
      final scale = OrdinalScale();
      scale.domain = categories;
      scale.range = [0, plotWidth];
      return scale;
    }
  }

  Scale _setupYScale(_ChartData chartData, double plotHeight) {
    if (chartData.yColumn == null) {
      final scale = LinearScale();
      scale.domain = [0, 1];
      scale.range = [plotHeight, 0];
      return scale;
    }

    final yValues = chartData.data
        .map((d) => d[chartData.yColumn])
        .where((v) => v != null)
        .toList();

    if (yValues.isEmpty) {
      final scale = LinearScale();
      scale.domain = [0, 1];
      scale.range = [plotHeight, 0];
      return scale;
    }

    final numValues = yValues.map((v) => (v as num).toDouble()).toList();
    final scale = LinearScale();
    scale.range = [plotHeight, 0];
    scale.setBounds(numValues, null, chartData.geometries);
    return scale;
  }

  Scale? _setupY2Scale(_ChartData chartData, double plotHeight) {
    if (chartData.y2Column == null) {
      return null;
    }

    final y2Values = chartData.data
        .map((d) => d[chartData.y2Column])
        .where((v) => v != null)
        .toList();

    if (y2Values.isEmpty) {
      return null;
    }

    final numValues = y2Values.map((v) => (v as num).toDouble()).toList();
    final scale = LinearScale();
    scale.range = [plotHeight, 0];
    scale.setBounds(numValues, null, chartData.geometries);
    return scale;
  }

  Map<String, String> _setupColorScale(_ChartData chartData) {
    final colorMap = <String, String>{};
    if (chartData.colorColumn == null) {
      return colorMap;
    }

    final colorValues = chartData.data
        .map((d) => d[chartData.colorColumn])
        .where((v) => v != null)
        .toSet()
        .toList();
    final defaultColors = [
      '#1f77b4',
      '#ff7f0e',
      '#2ca02c',
      '#d62728',
      '#9467bd',
      '#8c564b'
    ];

    for (int i = 0; i < colorValues.length; i++) {
      colorMap[colorValues[i].toString()] =
          defaultColors[i % defaultColors.length];
    }

    return colorMap;
  }

  Map<String, double> _setupSizeScale(_ChartData chartData) {
    final sizeMap = <String, double>{};
    if (chartData.sizeColumn == null) {
      return sizeMap;
    }

    final sizeValues = chartData.data
        .map((d) => d[chartData.sizeColumn])
        .where((v) => v != null)
        .toList();
    if (sizeValues.isEmpty) {
      return sizeMap;
    }

    final numValues = sizeValues.map((v) => (v as num).toDouble()).toList();
    final min = numValues.reduce((a, b) => a < b ? a : b);
    final max = numValues.reduce((a, b) => a > b ? a : b);

    for (final value in sizeValues) {
      final numValue = (value as num).toDouble();
      final normalized = (numValue - min) / (max - min);
      sizeMap[value.toString()] = 2 + normalized * 8; // Scale from 2 to 10
    }

    return sizeMap;
  }

  void _renderBackground(StringBuffer buffer, Rect plotArea, ChartTheme theme) {
    // Render plot area background if needed
    buffer.writeln(
        '  <rect x="${plotArea.left}" y="${plotArea.top}" width="${plotArea.width}" height="${plotArea.height}" fill="none"/>');
  }

  void _renderGrid(
      StringBuffer buffer, Rect plotArea, Scale xScale, Scale yScale, ChartTheme theme) {
    final gridColor = '#e0e0e0';

    // Vertical grid lines - use Wilkinson Extended ticks
    if (xScale is LinearScale) {
      final ticks = xScale.getTicks();
      for (final tick in ticks) {
        final x = plotArea.left + xScale.scale(tick);
        buffer.writeln(
            '  <line x1="$x" y1="${plotArea.top}" x2="$x" y2="${plotArea.top + plotArea.height}" stroke="$gridColor" stroke-width="1"/>');
      }
    }

    // Horizontal grid lines - use Wilkinson Extended ticks
    if (yScale is LinearScale) {
      final ticks = yScale.getTicks();
      for (final tick in ticks) {
        final y = plotArea.top + yScale.scale(tick);
        buffer.writeln(
            '  <line x1="${plotArea.left}" y1="$y" x2="${plotArea.left + plotArea.width}" y2="$y" stroke="$gridColor" stroke-width="1"/>');
      }
    }
  }

  void _renderGeometries(
    StringBuffer buffer,
    Rect plotArea,
    _ChartData chartData,
    Scale xScale,
    Scale yScale,
    Scale? y2Scale,
    Map<String, String> colorScale,
    Map<String, double> sizeScale,
  ) {
    for (final geometry in chartData.geometries) {
      if (geometry is PointGeometry || geometry is BubbleGeometry) {
        _renderPoints(
            buffer, plotArea, chartData, xScale, yScale, colorScale, sizeScale);
      } else if (geometry is LineGeometry) {
        _renderLines(buffer, plotArea, chartData, xScale, yScale, colorScale);
      } else if (geometry is BarGeometry) {
        _renderBars(buffer, plotArea, chartData, xScale, yScale, colorScale);
      }
    }
  }

  void _renderPoints(
      StringBuffer buffer,
      Rect plotArea,
      _ChartData chartData,
      Scale xScale,
      Scale yScale,
      Map<String, String> colorScale,
      Map<String, double> sizeScale) {
    for (final point in chartData.data) {
      final x = plotArea.left + xScale.scale(point[chartData.xColumn]);
      final y = plotArea.top + yScale.scale(point[chartData.yColumn]);
      final color =
          colorScale[point[chartData.colorColumn]?.toString()] ?? '#1f77b4';
      final size = sizeScale[point[chartData.sizeColumn]?.toString()] ?? 3.0;

      buffer.writeln('  <circle cx="$x" cy="$y" r="$size" fill="$color"/>');
    }
  }

  void _renderLines(StringBuffer buffer, Rect plotArea, _ChartData chartData,
      Scale xScale, Scale yScale, Map<String, String> colorScale) {
    if (chartData.data.length < 2) return;

    final points = chartData.data.map((point) {
      final x = plotArea.left + xScale.scale(point[chartData.xColumn]);
      final y = plotArea.top + yScale.scale(point[chartData.yColumn]);
      return '$x,$y';
    }).join(' ');

    final color =
        colorScale.values.isNotEmpty ? colorScale.values.first : '#1f77b4';
    buffer.writeln(
        '  <polyline points="$points" stroke="$color" stroke-width="2" fill="none"/>');
  }

  void _renderBars(StringBuffer buffer, Rect plotArea, _ChartData chartData,
      Scale xScale, Scale yScale, Map<String, String> colorScale) {
    final barWidth = plotArea.width / chartData.data.length * 0.8;

    for (int i = 0; i < chartData.data.length; i++) {
      final point = chartData.data[i];
      final x =
          plotArea.left + xScale.scale(point[chartData.xColumn]) - barWidth / 2;
      final yValue = yScale.scale(point[chartData.yColumn]);
      final y = plotArea.top + yValue;
      final height = plotArea.height - yValue;
      final color =
          colorScale[point[chartData.colorColumn]?.toString()] ?? '#1f77b4';

      buffer.writeln(
          '  <rect x="$x" y="$y" width="$barWidth" height="$height" fill="$color"/>');
    }
  }

  void _renderAxes(
    StringBuffer buffer,
    Rect plotArea,
    Scale xScale,
    Scale yScale,
    Scale? y2Scale,
    ChartTheme theme,
  ) {
    final axisColor = '#333333';

    // X axis
    buffer.writeln(
        '  <line x1="${plotArea.left}" y1="${plotArea.top + plotArea.height}" x2="${plotArea.left + plotArea.width}" y2="${plotArea.top + plotArea.height}" stroke="$axisColor" stroke-width="1"/>');

    // Y axis
    buffer.writeln(
        '  <line x1="${plotArea.left}" y1="${plotArea.top}" x2="${plotArea.left}" y2="${plotArea.top + plotArea.height}" stroke="$axisColor" stroke-width="1"/>');

    // X axis labels - use Wilkinson Extended ticks
    if (xScale is LinearScale) {
      final ticks = xScale.getTicks();
      for (final tick in ticks) {
        final x = plotArea.left + xScale.scale(tick);
        final y = plotArea.top + plotArea.height + 20;
        buffer.writeln(
            '  <text x="$x" y="$y" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="$axisColor">');
        buffer.writeln('    ${xScale.formatLabel(tick)}');
        buffer.writeln('  </text>');
      }
    } else if (xScale is OrdinalScale) {
      final categories = xScale.domain;
      for (final category in categories) {
        final x = plotArea.left + xScale.scale(category);
        final y = plotArea.top + plotArea.height + 20;
        buffer.writeln(
            '  <text x="$x" y="$y" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="$axisColor">');
        buffer.writeln('    $category');
        buffer.writeln('  </text>');
      }
    }

    // Y axis labels - use Wilkinson Extended ticks
    if (yScale is LinearScale) {
      final ticks = yScale.getTicks();
      for (final tick in ticks) {
        final x = plotArea.left - 10;
        final y = plotArea.top + yScale.scale(tick) + 4;
        buffer.writeln(
            '  <text x="$x" y="$y" text-anchor="end" font-family="Arial, sans-serif" font-size="12" fill="$axisColor">');
        buffer.writeln('    ${yScale.formatLabel(tick)}');
        buffer.writeln('  </text>');
      }
    }
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }
}

// Helper class to hold extracted chart data
class _ChartData {
  final List<Map<String, dynamic>> data;
  final String? xColumn;
  final String? yColumn;
  final String? y2Column;
  final String? colorColumn;
  final String? sizeColumn;
  final List<Geometry> geometries;
  final ChartTheme theme;

  _ChartData({
    required this.data,
    this.xColumn,
    this.yColumn,
    this.y2Column,
    this.colorColumn,
    this.sizeColumn,
    required this.geometries,
    required this.theme,
  });
}
