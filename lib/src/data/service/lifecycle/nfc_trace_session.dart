import '../../../domain/entities/nfc_trace_event.dart';
import '../../../domain/enums/nfc_trace_step.dart';

/// Quản lý phát sự kiện breadcrumb [NfcTraceEvent] cho 1 phiên đọc chip.
///
/// Mỗi phiên khởi tạo với 1 `sessionId` duy nhất, ghi lại thời điểm bắt đầu
/// và tự động tính `elapsed` cho mỗi sự kiện phát ra.
class NfcTraceSession {
  NfcTraceSession(
    this.sessionId,
    void Function(NfcTraceEvent event)? onTrace, {
    this.onStep,
  })  : _onTrace = onTrace ?? _noop,
        startedAt = DateTime.now();

  final String sessionId;
  final void Function(NfcTraceStep step)? onStep;
  final void Function(NfcTraceEvent event) _onTrace;
  final DateTime startedAt;

  /// Phát 1 sự kiện [NfcTraceEvent] và thông báo bước [onStep] (nếu có).
  void emit(
    NfcTraceStep step, {
    int? sw1,
    int? sw2,
    int? bytes,
    String? detail,
  }) {
    onStep?.call(step);
    final now = DateTime.now();
    _onTrace(
      NfcTraceEvent(
        sessionId: sessionId,
        step: step,
        timestamp: now,
        elapsed: now.difference(startedAt),
        sw1: sw1,
        sw2: sw2,
        dataLengthBytes: bytes,
        detail: detail,
      ),
    );
  }

  static void _noop(NfcTraceEvent _) {}

  /// Giới hạn độ dài chi tiết để an toàn khi log (chống chuỗi quá dài).
  /// Nội dung ở đây là text kỹ thuật giao thức, không phải nội dung dữ liệu thẻ.
  static String? sanitize(String? value, {int maxLength = 200}) {
    if (value == null) return null;
    final s = value.trim();
    if (s.isEmpty) return null;
    return s.length > maxLength ? '${s.substring(0, maxLength)}…' : s;
  }
}
