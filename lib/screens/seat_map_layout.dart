import '../models/booking_models.dart';

class SeatMapBoardMetrics {
  const SeatMapBoardMetrics({
    required this.columns,
    required this.rows,
    required this.cellSize,
    required this.boardWidth,
    required this.boardHeight,
    required this.viewportHeight,
    required this.initialScale,
  });

  final int columns;
  final int rows;
  final double cellSize;
  final double boardWidth;
  final double boardHeight;
  final double viewportHeight;
  final double initialScale;
}

SeatMapBoardMetrics computeSeatMapBoardMetrics({
  required List<SeatMapItem> seats,
  required double maxWidth,
  required bool compact,
}) {
  const gap = 8.0;
  const contentPadding = 24.0;

  final columns = seats.fold<int>(
    1,
    (max, item) => item.x + item.w > max ? (item.x + item.w).ceil() : max,
  );
  final rows = seats.fold<int>(
    1,
    (max, item) => item.y + item.h > max ? (item.y + item.h).ceil() : max,
  );
  final cellSize = (compact ? 54.0 : (maxWidth - gap * (columns - 1)) / columns)
      .clamp(48.0, 68.0)
      .toDouble();
  final boardWidth = columns * cellSize + (columns - 1) * gap;
  final boardHeight = rows * cellSize + (rows - 1) * gap;
  final contentWidth = boardWidth + contentPadding;
  final contentHeight = boardHeight + contentPadding;
  final minViewportHeight = compact ? 260.0 : 320.0;
  final maxViewportHeight = compact ? 380.0 : 520.0;
  final viewportHeight = contentHeight < minViewportHeight
      ? contentHeight
      : contentHeight.clamp(minViewportHeight, maxViewportHeight).toDouble();
  final initialScale = (maxWidth / contentWidth).clamp(0.55, 1.0).toDouble();

  return SeatMapBoardMetrics(
    columns: columns,
    rows: rows,
    cellSize: cellSize,
    boardWidth: boardWidth,
    boardHeight: boardHeight,
    viewportHeight: viewportHeight,
    initialScale: initialScale,
  );
}
