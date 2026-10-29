import 'package:dmrtd/dmrtd.dart';

import '../../../domain/entities/nfc_failure.dart';
import '../../../domain/entities/nfc_warning.dart';
import '../../../domain/enums/nfc_read_stage.dart';
import '../../../domain/enums/nfc_trace_step.dart';
import '../../../domain/enums/nfc_warning_type.dart';
import '../lifecycle/nfc_trace_session.dart';
import '../nfc_error_classifier.dart';

/// Trợ giúp xử lý lỗi và định dạng metadata khi đọc các Data Group.
class DgReaderHelper {
  const DgReaderHelper._();

  /// Xử lý tập trung ngoại lệ khi đọc Data Group:
  /// - Rethrow ngay lập tức nếu là [NfcFailure] hoặc [tagLost] để huỷ phiên đọc.
  /// - Với các lỗi không-fatal: bóc tách status word SW1/SW2, format chi tiết kỹ thuật
  ///   đã sanitize, ghi vào [warnings] và phát trace event chẩn đoán.
  static void handleDgReadError({
    required NfcTraceStep step,
    required NfcWarningType warningType,
    required Object error,
    required NfcTraceSession trace,
    required List<NfcWarning> warnings,
  }) {
    if (error is NfcFailure) throw error;
    if (NfcErrorClassifier.isTagLostError(error)) {
      throw NfcErrorClassifier.tagLost(stage: NfcReadStage.reading);
    }

    final sw = extractStatusWords(error);
    final detail = formatErrorDetail(error, sw1: sw.sw1, sw2: sw.sw2);

    warnings.add(NfcWarning(warningType, detail: detail));
    trace.emit(
      step,
      sw1: sw.sw1,
      sw2: sw.sw2,
      detail: 'failed: $detail',
    );
  }

  /// Bóc tách status words (SW1, SW2) từ exception nếu có.
  static ({int? sw1, int? sw2}) extractStatusWords(Object error) {
    if (error is PassportError) {
      return (sw1: error.code?.sw1, sw2: error.code?.sw2);
    }
    try {
      final dynamic dyn = error;
      final dynamic sw = dyn.code ?? dyn.sw;
      if (sw != null) {
        final sw1 = sw.sw1;
        final sw2 = sw.sw2;
        if (sw1 is int && sw2 is int) {
          return (sw1: sw1, sw2: sw2);
        }
      }
    } catch (_) {}
    return (sw1: null, sw2: null);
  }

  /// Định dạng chi tiết lỗi kỹ thuật kèm mã SW (nếu có) và sanitize an toàn.
  static String formatErrorDetail(Object error, {int? sw1, int? sw2}) {
    final buffer = StringBuffer();
    if (sw1 != null && sw2 != null) {
      final hex1 = sw1.toRadixString(16).padLeft(2, '0').toUpperCase();
      final hex2 = sw2.toRadixString(16).padLeft(2, '0').toUpperCase();
      buffer.write('SW=$hex1$hex2 ');
    }
    if (error is PassportError) {
      buffer.write(error.message);
    } else {
      buffer.write(error.toString());
    }
    return NfcTraceSession.sanitize(buffer.toString()) ?? 'unknown error';
  }
}
