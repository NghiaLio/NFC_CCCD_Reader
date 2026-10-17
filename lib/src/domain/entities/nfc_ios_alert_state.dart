import '../enums/nfc_trace_step.dart';
import 'nfc_failure.dart';

/// Trạng thái phiên đọc để app dựng chữ cho sheet NFC của iOS.
///
/// Package không kèm chuỗi hiển thị — app nhận state này qua
/// [NfcIosAlertBuilder] và tự trả chuỗi (đa ngôn ngữ) tương ứng.
class NfcIosAlertState {
  const NfcIosAlertState({
    required this.step,
    required this.progress,
    this.failure,
  });

  /// Bước hiện tại của phiên đọc.
  final NfcTraceStep step;

  /// Tiến độ ước lượng theo bước, trong khoảng 0..1.
  final double progress;

  /// Khác `null` khi [step] là [NfcTraceStep.failed].
  final NfcFailure? failure;
}

/// Dựng chữ cho sheet NFC của iOS. Trả về `null` để giữ nguyên chữ đang hiển thị.
typedef NfcIosAlertBuilder = String? Function(NfcIosAlertState state);
