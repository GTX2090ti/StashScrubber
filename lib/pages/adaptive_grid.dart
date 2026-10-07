/// 根据可用宽度自适应网格列数（手机 2-3 列，iPad 横屏最多 6 列）
int adaptiveColumnCount(double width, {int minCols = 2}) {
  if (width >= 1400) return 6;
  if (width >= 1100) return 5;
  if (width >= 800) return 4;
  if (width >= 600) return 3;
  return minCols;
}
