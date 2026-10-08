import 'dart:math';

/// Sinh 1 ID phiên đọc dạng UUID v4 (không phụ thuộc package ngoài).
///
/// Mỗi `read()` sinh 1 ID riêng — dùng để nhóm log (breadcrumb, kết quả, lỗi)
/// của cùng 1 lượt quét trong hệ thống phía trên.
String generateNfcSessionId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  final hex =
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
