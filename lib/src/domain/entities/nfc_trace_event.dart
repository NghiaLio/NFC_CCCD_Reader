import '../enums/nfc_trace_step.dart';

/// 1 sự kiện breadcrumb trong phiên đọc — phát ra qua `NfcCccdReader.traceStream`.
///
/// **Chỉ chứa metadata an toàn để log**: bước, thời gian, mã trạng thái APDU
/// (SW1/SW2), độ dài dữ liệu (byte) và chi tiết kỹ thuật ĐÃ SANITIZE.
///
/// **KHÔNG bao giờ** chứa PII (MRZ, tên, số định danh, ảnh, key) hay nội dung
/// APDU đã giải mã — app có thể đẩy thẳng event này lên Sentry/Crashlytics sau
/// khi thêm thông tin thiết bị (OS, model).
class NfcTraceEvent {
  /// ID phiên đọc — chung với `NfcReadResult.sessionId`/`NfcFailure.sessionId`,
  /// dùng để nhóm mọi event của cùng 1 lượt quét trong log.
  final String sessionId;

  /// Bước vừa xảy ra.
  final NfcTraceStep step;

  /// Thời điểm sự kiện.
  final DateTime timestamp;

  /// Thời gian trôi từ khi `read()` bắt đầu đến sự kiện này.
  final Duration elapsed;

  /// Byte 1 của status word APDU (nếu bước này liên quan 1 APDU lỗi/thành công).
  final int? sw1;

  /// Byte 2 của status word APDU.
  final int? sw2;

  /// Độ dài dữ liệu đã đọc (byte) — chỉ dùng cho các bước đọc dữ liệu
  /// (DG2 ảnh, DG13, AA). Không kèm nội dung dữ liệu.
  final int? dataLengthBytes;

  /// Chi tiết kỹ thuật ĐÃ SANITIZE (không PII) — ví dụ tên class lỗi gốc
  /// (`'PACEError'`), hoặc fingerprint SHA-256 của challenge/signature AA.
  final String? detail;

  const NfcTraceEvent({
    required this.sessionId,
    required this.step,
    required this.timestamp,
    required this.elapsed,
    this.sw1,
    this.sw2,
    this.dataLengthBytes,
    this.detail,
  });

  @override
  String toString() => 'NfcTraceEvent(session: $sessionId, step: $step, '
      'elapsed: ${elapsed.inMilliseconds}ms'
      '${sw1 != null ? ', sw: ${_hex(sw1!)}${_hex(sw2!)}' : ''}'
      '${dataLengthBytes != null ? ', bytes: $dataLengthBytes' : ''}'
      '${detail != null ? ', detail: $detail' : ''})';

  static String _hex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
}
