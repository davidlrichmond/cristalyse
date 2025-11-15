import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'geometry.dart';
import 'render_models.dart';
import 'scale.dart';
import 'util/helper.dart';
import '../themes/chart_theme.dart';

/// Calculates chart geometry (positions, sizes, colors) independently of rendering.
///
/// This class extracts all geometric calculations from the rendering layer,
/// enabling:
/// - Shared calculation logic between Canvas and SVG renderers
/// - Unit testing of layout without rendering
/// - Cleaner separation of concerns
///
/// All methods return full geometry with no animation applied. Animation
/// is the responsibility of the rendering layer.
class GeometryCalculator {
  final List<Map<String, dynamic>> data;
  final String? xColumn;
  final String? yColumn;
  final String? colorColumn;
  final String? sizeColumn;
  final String? pieValueColumn;
  final String? pieCategoryColumn;
  final String? heatMapXColumn;
  final String? heatMapYColumn;
  final String? heatMapValueColumn;
  final ChartTheme theme;
  final bool coordFlipped;

  const GeometryCalculator({
    required this.data,
    this.xColumn,
    this.yColumn,
    this.colorColumn,
    this.sizeColumn,
    this.pieValueColumn,
    this.pieCategoryColumn,
    this.heatMapXColumn,
    this.heatMapYColumn,
    this.heatMapValueColumn,
    required this.theme,
    this.coordFlipped = false,
  });

  /// Calculates geometry for a single bar.
  ///
  /// Extracted from AnimatedChartPainter._drawSingleBar (lines 1003-1120).
  ///
  /// Returns null if the bar cannot be drawn (invalid scales, empty rect, etc.).
  BarRenderData? calculateSingleBar(
    dynamic xValForPosition,
    double yValForBar,
    Scale xScale,
    Scale yScale,
    ColorScale colorScale,
    BarGeometry geometry,
    Map<String, dynamic> dataPoint,
    Rect plotArea, {
    double? customX,
    double? customWidth,
    double yStackOffset = 0,
  }) {
    // Priority: geometry.color > colorScale > theme fallback
    final dynamic colorOrGradient;
    if (geometry.color != null) {
      colorOrGradient = geometry.color!;
    } else if (colorColumn != null) {
      colorOrGradient = colorScale.scale(dataPoint[colorColumn]);
    } else {
      colorOrGradient = theme.colorPalette.isNotEmpty
          ? theme.colorPalette.first
          : theme.primaryColor;
    }

    Rect barRect;

    if (coordFlipped) {
      // Horizontal bars
      if (yScale is! OrdinalScale || xScale is! LinearScale) {
        return null;
      }

      final yPos = plotArea.top + yScale.scale(xValForPosition);
      final barHeight = yScale.bandWidth * geometry.width;
      final yCenter = yPos + (yScale.bandWidth * (1 - geometry.width)) / 2;

      final xStart = plotArea.left + xScale.scale(yStackOffset);
      final xEnd = plotArea.left + xScale.scale(yValForBar + yStackOffset);
      final barWidth = xEnd - xStart;

      barRect = Rect.fromLTWH(
        xStart,
        yCenter,
        barWidth.isFinite ? barWidth : 0,
        barHeight.isFinite ? barHeight : 0,
      );
    } else {
      // Vertical bars
      if (xScale is! OrdinalScale || yScale is! LinearScale) {
        return null;
      }

      double xPos;
      double barWidth;

      if (customX != null && customWidth != null) {
        // For grouped bars - use provided position and width
        xPos = customX;
        barWidth = customWidth;
      } else {
        // For simple/stacked bars - center within band
        xPos = plotArea.left + xScale.scale(xValForPosition);
        barWidth = xScale.bandWidth * geometry.width;
        xPos += (xScale.bandWidth * (1 - geometry.width)) / 2;
      }

      final yStart = plotArea.top + yScale.scale(yStackOffset);
      final yEnd = plotArea.top + yScale.scale(yValForBar + yStackOffset);
      final barHeight = yStart - yEnd;

      barRect = Rect.fromLTWH(
        xPos.isFinite ? xPos : 0,
        yEnd, // Full height, no animation
        barWidth.isFinite ? barWidth : 0,
        barHeight.isFinite ? barHeight : 0,
      );
    }

    if (!barRect.isFinite || barRect.isEmpty) {
      return null;
    }

    return BarRenderData(
      rect: barRect,
      colorOrGradient: colorOrGradient,
      alpha: geometry.alpha,
      borderRadius: geometry.borderRadius,
      borderWidth: geometry.borderWidth,
      borderColor: geometry.borderWidth > 0 ? theme.borderColor : null,
      dataPoint: dataPoint,
    );
  }

  /// Calculates geometry for simple (non-grouped, non-stacked) bars.
  ///
  /// Extracted from AnimatedChartPainter._drawSimpleBars (lines 791-831).
  List<BarRenderData> calculateSimpleBars(
    BarGeometry geometry,
    Scale xScale,
    Scale yScale,
    ColorScale colorScale,
    Rect plotArea,
    String? yCol,
  ) {
    final bars = <BarRenderData>[];

    for (final point in data) {
      final x = point[xColumn];
      final y = getNumericValue(point[yCol]);

      if (y == null || !y.isFinite) continue;

      final bar = calculateSingleBar(
        x,
        y,
        xScale,
        yScale,
        colorScale,
        geometry,
        point,
        plotArea,
      );

      if (bar != null) {
        bars.add(bar);
      }
    }

    return bars;
  }

  /// Calculates geometry for grouped bars.
  ///
  /// Extracted from AnimatedChartPainter._drawGroupedBars (lines 833-921).
  List<BarRenderData> calculateGroupedBars(
    BarGeometry geometry,
    Scale xScale,
    Scale yScale,
    ColorScale colorScale,
    Rect plotArea,
    String? yCol,
  ) {
    if (colorColumn == null) return [];

    final bars = <BarRenderData>[];

    // Group data by X value
    final groups = <dynamic, Map<dynamic, double>>{};
    for (final point in data) {
      final x = point[xColumn];
      final y = getNumericValue(point[yCol]);
      final color = point[colorColumn];

      if (y == null || !y.isFinite) continue;

      groups.putIfAbsent(x, () => {})[color] = y;
    }

    // Get all unique colors to determine bar count per group
    final allColors = data.map((d) => d[colorColumn]).toSet().toList();
    final colorCount = allColors.length;

    for (final groupEntry in groups.entries) {
      final x = groupEntry.key;
      final colorValues = groupEntry.value;

      // Calculate group layout
      double basePosition;
      double totalGroupWidth;

      if (xScale is OrdinalScale) {
        final centerPos = plotArea.left + xScale.bandCenter(x);
        totalGroupWidth = xScale.bandWidth * geometry.width;
        basePosition = centerPos - (totalGroupWidth / 2);
      } else {
        basePosition = plotArea.left + xScale.scale(x) - 20;
        totalGroupWidth = 40 * geometry.width;
      }

      final barWidth = totalGroupWidth / colorCount;

      // Create bars for each color in the group
      int colorIndex = 0;
      for (final color in allColors) {
        final value = colorValues[color];
        if (value == null) {
          colorIndex++;
          continue;
        }

        final barX = basePosition + colorIndex * barWidth;

        final bar = calculateSingleBar(
          x,
          value,
          xScale,
          yScale,
          colorScale,
          geometry,
          {colorColumn!: color},
          plotArea,
          customX: barX,
          customWidth: barWidth,
        );

        if (bar != null) {
          bars.add(bar);
        }

        colorIndex++;
      }
    }

    return bars;
  }

  /// Calculates geometry for stacked bars.
  ///
  /// Extracted from AnimatedChartPainter._drawStackedBars (lines 923-1001).
  List<BarRenderData> calculateStackedBars(
    BarGeometry geometry,
    Scale xScale,
    Scale yScale,
    ColorScale colorScale,
    Rect plotArea,
    String? yCol,
  ) {
    final bars = <BarRenderData>[];

    // Group data by X value
    final groups = <dynamic, List<Map<String, dynamic>>>{};
    for (final point in data) {
      final x = point[xColumn];
      groups.putIfAbsent(x, () => []).add(point);
    }

    for (final groupEntry in groups.entries) {
      final x = groupEntry.key;
      final groupData = groupEntry.value;

      // Sort by color for consistent stacking order
      groupData.sort((a, b) {
        final aColor = a[colorColumn]?.toString() ?? '';
        final bColor = b[colorColumn]?.toString() ?? '';
        return aColor.compareTo(bColor);
      });

      double cumulativeValue = 0;
      for (final point in groupData) {
        final y = getNumericValue(point[yCol]);
        if (y == null || !y.isFinite || y <= 0) continue;

        final bar = calculateSingleBar(
          x,
          y,
          xScale,
          yScale,
          colorScale,
          geometry,
          point,
          plotArea,
          yStackOffset: cumulativeValue,
        );

        if (bar != null) {
          bars.add(bar);
        }

        cumulativeValue += y;
      }
    }

    return bars;
  }

  /// Calculates geometry for a single line.
  ///
  /// Extracted from AnimatedChartPainter._drawSingleLineAnimated (lines 1505-1577).
  ///
  /// Returns null if the line cannot be drawn (< 2 points, invalid data, etc.).
  LineRenderData? calculateLine(
    LineGeometry geometry,
    Scale xScale,
    Scale yScale,
    Color color,
    Rect plotArea,
    List<Map<String, dynamic>> lineData,
    String? yCol,
  ) {
    if (yCol == null) return null;

    // Sort data by x value for proper line connection
    final sortedData = List<Map<String, dynamic>>.from(lineData);
    sortedData.sort((a, b) {
      final aXValue = a[xColumn];
      final bXValue = b[xColumn];

      if (aXValue == null && bXValue == null) return 0;
      if (aXValue == null) return -1;
      if (bXValue == null) return 1;

      // Get the actual plotted X position for proper ordering
      double aXPosition, bXPosition;

      if (xScale is OrdinalScale) {
        aXPosition = xScale.bandCenter(aXValue);
        bXPosition = xScale.bandCenter(bXValue);
      } else {
        final aXNum = getNumericValue(aXValue) ?? 0;
        final bXNum = getNumericValue(bXValue) ?? 0;
        aXPosition = xScale.scale(aXNum);
        bXPosition = xScale.scale(bXNum);
      }

      return aXPosition.compareTo(bXPosition);
    });

    final points = <Offset>[];

    for (final point in sortedData) {
      final xRawValue = point[xColumn];
      final yVal = getNumericValue(point[yCol]);

      if (xRawValue == null || yVal == null) {
        continue;
      }

      // Handle both ordinal and continuous X-scales
      double screenX;
      if (xScale is OrdinalScale) {
        screenX = plotArea.left + xScale.bandCenter(xRawValue);
      } else {
        final xVal = getNumericValue(xRawValue);
        if (xVal == null) continue;
        screenX = plotArea.left + xScale.scale(xVal);
      }

      final screenY = plotArea.top + yScale.scale(yVal);

      if (!screenX.isFinite || !screenY.isFinite) {
        continue;
      }

      points.add(Offset(screenX, screenY));
    }

    if (points.length < 2) {
      return null;
    }

    return LineRenderData(
      points: points,
      color: color,
      strokeWidth: geometry.strokeWidth,
      alpha: geometry.alpha,
      style: geometry.style,
    );
  }

  /// Calculates geometry for all lines (handles grouping by color).
  ///
  /// Extracted from AnimatedChartPainter._drawLinesAnimated (lines 1458-1503).
  List<LineRenderData> calculateLines(
    LineGeometry geometry,
    Scale xScale,
    Scale yScale,
    ColorScale colorScale,
    Rect plotArea,
    String? yCol,
  ) {
    if (yCol == null) return [];

    final lines = <LineRenderData>[];

    if (colorColumn != null) {
      // Group by color and draw separate lines
      final groupedData = <dynamic, List<Map<String, dynamic>>>{};
      for (final point in data) {
        final colorValue = point[colorColumn];
        groupedData.putIfAbsent(colorValue, () => []).add(point);
      }

      for (final entry in groupedData.entries) {
        final colorValue = entry.key;
        final groupData = entry.value;
        final lineColor = geometry.color ?? colorScale.scale(colorValue);

        final line = calculateLine(
          geometry,
          xScale,
          yScale,
          lineColor,
          plotArea,
          groupData,
          yCol,
        );

        if (line != null) {
          lines.add(line);
        }
      }
    } else {
      // Draw single line for all data
      final lineColor = geometry.color ??
          (theme.colorPalette.isNotEmpty
              ? theme.colorPalette.first
              : theme.primaryColor);

      final line = calculateLine(
        geometry,
        xScale,
        yScale,
        lineColor,
        plotArea,
        data,
        yCol,
      );

      if (line != null) {
        lines.add(line);
      }
    }

    return lines;
  }

  /// Calculates geometry for scatter points.
  ///
  /// Extracted from AnimatedChartPainter._drawPointsAnimated (lines 1122-1269).
  List<PointRenderData> calculatePoints(
    PointGeometry geometry,
    Scale xScale,
    Scale yScale,
    ColorScale colorScale,
    SizeScale sizeScale,
    Rect plotArea,
    String? yCol,
  ) {
    if (yCol == null) return [];

    final points = <PointRenderData>[];

    for (final point in data) {
      final xRawValue = point[xColumn];
      final y = getNumericValue(point[yCol]);

      if (xRawValue == null || y == null) continue;

      // Handle both ordinal and continuous X-scales
      double pointX;
      if (xScale is OrdinalScale) {
        pointX = plotArea.left + xScale.bandCenter(xRawValue);
      } else {
        final x = getNumericValue(xRawValue);
        if (x == null) continue;
        pointX = plotArea.left + xScale.scale(x);
      }

      final pointY = plotArea.top + yScale.scale(y);

      if (!pointX.isFinite || !pointY.isFinite) {
        continue;
      }

      // Priority: geometry.color > colorScale > theme fallback
      final dynamic colorOrGradient;
      if (geometry.color != null) {
        colorOrGradient = geometry.color!;
      } else if (colorColumn != null) {
        colorOrGradient = colorScale.scale(point[colorColumn]);
      } else {
        colorOrGradient = theme.colorPalette.isNotEmpty
            ? theme.colorPalette.first
            : theme.primaryColor;
      }

      final size = sizeColumn != null
          ? sizeScale.scale(point[sizeColumn])
          : theme.pointSizeDefault;

      points.add(PointRenderData(
        position: Offset(pointX, pointY),
        size: size,
        colorOrGradient: colorOrGradient,
        alpha: geometry.alpha,
        shape: geometry.shape,
        borderWidth: geometry.borderWidth,
        borderColor: geometry.borderWidth > 0 ? theme.borderColor : null,
        dataPoint: point,
      ));
    }

    return points;
  }

  /// Calculates geometry for pie chart slices.
  ///
  /// Extracted from AnimatedChartPainter._drawPieAnimated (lines 2077-2234).
  ///
  /// Returns FULL slice data (no animation applied).
  List<PieSliceData> calculatePieSlices(
    PieGeometry geometry,
    ColorScale colorScale,
    Rect plotArea,
  ) {
    // Use pie-specific columns or fall back to regular columns
    final valueColumn = pieValueColumn ?? yColumn;
    final categoryColumn = pieCategoryColumn ?? colorColumn ?? xColumn;

    if (valueColumn == null || categoryColumn == null || data.isEmpty) {
      return [];
    }

    // Calculate center point of the plot area
    final center = Offset(
      plotArea.left + plotArea.width / 2,
      plotArea.top + plotArea.height / 2,
    );

    // Calculate radius based on plot area (leave margin for labels)
    final maxRadius = math.min(plotArea.width, plotArea.height) / 2 - 50;
    final outerRadius = math.min(geometry.outerRadius, maxRadius);
    final innerRadius = math.min(
      geometry.innerRadius,
      outerRadius * 0.8,
    ); // Ensure inner radius isn't too close to outer

    // Extract and calculate values
    final values =
        data.map((d) => getNumericValue(d[valueColumn]) ?? 0).toList();
    final total = values.fold<double>(0, (sum, val) => sum + val);

    if (total <= 0) return [];

    // Build pie slices
    final slices = <PieSliceData>[];
    double currentAngle = geometry.startAngle;

    for (int i = 0; i < data.length; i++) {
      final value = values[i];
      if (value <= 0) continue;

      final sweepAngle = (value / total) * 2 * math.pi;
      final category = data[i][categoryColumn];
      final sliceColor = colorScale.scale(category);

      // Calculate slice center for explosion effect
      Offset sliceCenter = center;
      if (geometry.explodeSlices) {
        final midAngle = currentAngle + sweepAngle / 2;
        sliceCenter = Offset(
          center.dx + math.cos(midAngle) * geometry.explodeDistance,
          center.dy + math.sin(midAngle) * geometry.explodeDistance,
        );
      }

      slices.add(PieSliceData(
        startAngle: currentAngle,
        sweepAngle: sweepAngle,
        center: sliceCenter,
        outerRadius: outerRadius,
        innerRadius: innerRadius,
        color: sliceColor,
        value: value,
        category: category.toString(),
        percentage: value / total,
        dataPoint: data[i],
      ));

      currentAngle += sweepAngle;
    }

    return slices;
  }

  /// Calculates geometry for heat map cells.
  ///
  /// Extracted from AnimatedChartPainter._drawHeatMapAnimated (lines 2292-2491).
  ///
  /// Returns FULL cell data (no animation applied).
  List<HeatMapCellData> calculateHeatMap(
    HeatMapGeometry geometry,
    GradientColorScale gradientColorScale,
    Rect plotArea,
  ) {
    // Use heat map specific columns
    final xCol = heatMapXColumn ?? xColumn;
    final yCol = heatMapYColumn ?? yColumn;
    final valueCol = heatMapValueColumn;

    if (valueCol == null) {
      throw ArgumentError(
        'Heat maps require heatMapValueColumn. '
        'Use .mappingHeatMap(x: "xCol", y: "yCol", value: "valueCol").',
      );
    }

    if (xCol == null || yCol == null || data.isEmpty) {
      return [];
    }

    // Get unique X and Y values to determine grid
    final xValues =
        data.map((d) => d[xCol]).where((v) => v != null).toSet().toList();
    final yValues =
        data.map((d) => d[yCol]).where((v) => v != null).toSet().toList();

    if (xValues.isEmpty || yValues.isEmpty) {
      return [];
    }

    // Sort values for consistent ordering using existing helper
    sortHeatMapValues(xValues);
    sortHeatMapValues(yValues);

    // Calculate cell dimensions considering spacing
    final totalSpacingX = geometry.cellSpacing * (xValues.length + 1);
    final totalSpacingY = geometry.cellSpacing * (yValues.length + 1);
    double cellWidth = (plotArea.width - totalSpacingX) / xValues.length;
    double cellHeight = (plotArea.height - totalSpacingY) / yValues.length;

    if (geometry.cellAspectRatio != null) {
      // Adjust cell dimensions to maintain aspect ratio
      final targetHeight = cellWidth / geometry.cellAspectRatio!;
      if (targetHeight < cellHeight) {
        cellHeight = targetHeight;
      } else {
        cellWidth = cellHeight * geometry.cellAspectRatio!;
      }
    }

    // Create a map for quick lookup
    final dataMap = <String, double>{};
    for (final point in data) {
      final x = point[xCol];
      final y = point[yCol];
      final value = getNumericValue(point[valueCol]);
      if (x != null && y != null && value != null) {
        final key = '${x}_$y';
        dataMap[key] = value;
      }
    }

    // Build heat map cells
    final cells = <HeatMapCellData>[];

    for (int xi = 0; xi < xValues.length; xi++) {
      for (int yi = 0; yi < yValues.length; yi++) {
        final xVal = xValues[xi];
        final yVal = yValues[yi];
        final key = '${xVal}_$yVal';
        final value = dataMap[key];

        // Calculate cell position with spacing
        final cellRect = Rect.fromLTWH(
          plotArea.left +
              geometry.cellSpacing +
              xi * (cellWidth + geometry.cellSpacing),
          plotArea.top +
              geometry.cellSpacing +
              yi * (cellHeight + geometry.cellSpacing),
          cellWidth,
          cellHeight,
        );

        // Use GradientColorScale to get color (removing duplication)
        final cellColor = value != null
            ? gradientColorScale.scale(value)
            : (geometry.nullValueColor ?? Colors.transparent);

        final normalizedValue =
            value != null ? gradientColorScale.normalize(value) : null;

        cells.add(HeatMapCellData(
          rect: cellRect,
          xValue: xVal,
          yValue: yVal,
          value: value,
          color: cellColor,
          normalizedValue: normalizedValue,
          xIndex: xi,
          yIndex: yi,
        ));
      }
    }

    return cells;
  }

  /// Calculates geometry for area charts.
  ///
  /// Extracted from AnimatedChartPainter._drawSingleArea (lines 1766-1812).
  ///
  /// Returns FULL area data (no animation applied).
  AreaRenderData? calculateArea(
    AreaGeometry geometry,
    Scale xScale,
    Scale yScale,
    Color color,
    Rect plotArea,
    List<Map<String, dynamic>> areaData,
    String? yCol,
  ) {
    if (yCol == null) return null;

    // Sort data by x value for proper area connection
    final sortedData = List<Map<String, dynamic>>.from(areaData);
    sortedData.sort((a, b) {
      final aX = getNumericValue(a[xColumn]) ?? 0;
      final bX = getNumericValue(b[xColumn]) ?? 0;
      return aX.compareTo(bX);
    });

    final points = <Offset>[];
    for (int i = 0; i < sortedData.length; i++) {
      final point = sortedData[i];
      final xRawValue = point[xColumn];
      final yVal = getNumericValue(point[yCol]);

      if (xRawValue == null || yVal == null) continue;

      // Handle both ordinal and continuous X-scales
      double screenX;
      if (xScale is OrdinalScale) {
        screenX = plotArea.left + xScale.bandCenter(xRawValue);
      } else {
        final xVal = getNumericValue(xRawValue);
        if (xVal == null) continue;
        screenX = plotArea.left + xScale.scale(xVal);
      }

      final screenY = plotArea.top + yScale.scale(yVal);

      if (!screenX.isFinite || !screenY.isFinite) {
        continue;
      }

      points.add(Offset(screenX, screenY));
    }

    if (points.length < 2) return null;

    // Calculate baseline Y for area fill
    final baselineY = plotArea.top + yScale.scale(0);

    return AreaRenderData(
      points: points,
      baselineY: baselineY,
      color: color,
      alpha: geometry.alpha,
      fillArea: geometry.fillArea,
      strokeWidth: geometry.strokeWidth,
    );
  }
}
