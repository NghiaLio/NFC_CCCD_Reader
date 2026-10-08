import 'package:dmrtd/dmrtd.dart';

import '../../domain/entities/nfc_error_details.dart';
import '../../domain/entities/nfc_failure.dart';
import '../../domain/enums/nfc_failure_type.dart';
import '../../domain/enums/nfc_read_stage.dart';

/// Map exception từ dmrtd sang [NfcFailure] kèm [NfcErrorDetails] (metadata:
/// SW1/SW2, root cause, chi tiết đã sanitize). Tách riêng khỏi service đọc chip
/// để test được logic phân loại KHÔNG CẦN thiết bị NFC thật — đây là vùng đã
/// gây 3 bug thật trong quá trình phát triển bản gốc (xem comment từng nhánh),
/// chỉ phát hiện được qua test thiết bị vì trước đó không có unit test.
///
/// [NfcErrorDetails.detail] ở đây chỉ chứa text giao thức/technical từ luồng
/// xác thực (PACE) — KHÔNG phải nội dung dữ liệu thẻ (MRZ/tên/ảnh), nên an
/// toàn để log. Không dùng string hiển thị.
class NfcErrorClassifier {
  const NfcErrorClassifier._();

  static const _maxDetailLength = 200;
  static const _tagLostRootCause = 'ComProviderError/NfcProviderError';

  static NfcFailure tagLost({String? rootCause, NfcReadStage? stage}) =>
      NfcFailure(
        NfcFailureType.tagLost,
        errorDetails: NfcErrorDetails(
          stage: stage,
          rootCause: rootCause ?? _tagLostRootCause,
        ),
      );

  static NfcFailure fromPassportError(PassportError e, {NfcReadStage? stage}) {
    final code = e.code;
    final details = NfcErrorDetails(
      sw1: code?.sw1,
      sw2: code?.sw2,
      stage: stage,
      rootCause: 'PassportError',
      detail: _safeDetail(e.message),
    );
    if (_isAuthFailedStatus(e)) {
      return NfcFailure(NfcFailureType.wrongCan, errorDetails: details);
    }
    if (isTagLostError(e)) {
      return NfcFailure(NfcFailureType.tagLost, errorDetails: details);
    }
    return NfcFailure(NfcFailureType.paceFailed, errorDetails: details);
  }

  /// BUG THẬT #1 đã gặp: khi CAN sai, dmrtd KHÔNG ném `PassportError` như
  /// dartdoc mô tả, mà ném `PACEError` ("Auth token from ICC and terminal are
  /// not the same") — 1 nhóm exception PACE riêng, ném thẳng từ `PACE.initSession`,
  /// không đi qua lớp bọc `PassportError`, và cũng KHÔNG được dmrtd export
  /// public (giống tình huống `CanKey`). Nếu chỉ bắt `on PassportError`, lỗi
  /// này thoát ra ngoài dạng chưa xác định → bị nuốt ở tầng gọi. Đây là
  /// catch-all cuối chuỗi: tới được đây nghĩa là đã đọc EF.CardAccess thành
  /// công, nên lỗi PACE còn lại gần như luôn là CAN sai.
  static NfcFailure fromGenericException(Object e, {NfcReadStage? stage}) {
    // BUG THẬT #2 đã gặp: MỌI bước PACE trong dmrtd đều tự bọc
    // `try { ... } on Exception catch (e) { throw PACEError("...: $e"); }`
    // quanh transceive APDU. Nếu rút thẻ giữa lúc trao đổi APDU trong PACE, lỗi
    // mất kết nối thật (`ComProviderError`/`NfcProviderError`) bị dmrtd bắt và
    // ném lại thành `PACEError`, xoá mất type gốc. `$e` trong dmrtd nội suy
    // chuỗi lỗi gốc vào message, nên tên class gốc vẫn còn trong
    // `PACEError.toString()` — dùng string-match tên class (không phải mã giao
    // thức thô) để khôi phục đúng type trước khi map.
    if (isTagLostError(e)) {
      return tagLost(rootCause: _rootCauseOf(e), stage: stage);
    }
    return NfcFailure(
      NfcFailureType.wrongCan,
      errorDetails: NfcErrorDetails(
        stage: stage,
        rootCause: _rootCauseOf(e),
        detail: _safeDetail(e.toString()),
      ),
    );
  }

  // sw=6300 = PACE auth token mismatch (sai CAN) — status word ISO 7816, so
  // trực tiếp field public thay vì string-match, vì `StatusWord` cũng không
  // được dmrtd export public.
  static bool _isAuthFailedStatus(PassportError e) {
    final code = e.code;
    return code != null && code.sw1 == 0x63 && code.sw2 == 0x00;
  }

  /// BUG THẬT #3 đã gặp: ban đầu chỉ kiểm tra `e is ComProviderError`, không
  /// tính tới việc dmrtd bọc lỗi mất kết nối vào exception khác (xem
  /// [fromGenericException]) — chỉ còn thấy tên class gốc qua nội suy chuỗi,
  /// không phải string-match mã lỗi giao thức thô.
  static bool isTagLostError(Object e) {
    if (e is ComProviderError || e is NfcProviderError) return true;
    final msg = e.toString().toLowerCase();
    return msg.contains('comprovidererror') ||
        msg.contains('nfcprovidererror') ||
        msg.contains('tag lost') ||
        msg.contains('taglost') ||
        msg.contains('transceive') ||
        msg.contains('session invalidated') ||
        msg.contains('disconnected');
  }

  /// Tên class/type của lỗi GỐC (đã bị dmrtd bọc) — dùng cho
  /// [NfcErrorDetails.rootCause]. Không chứa PII.
  static String _rootCauseOf(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('comprovidererror')) return 'ComProviderError';
    if (msg.contains('nfcprovidererror')) return 'NfcProviderError';
    if (msg.contains('paceerror')) return 'PACEError';
    if (msg.contains('passporterror')) return 'PassportError';
    return e.runtimeType.toString();
  }

  /// Giới hạn độ dài chi tiết để an toàn khi log (chống chuỗi quá dài).
  static String? _safeDetail(String? value) {
    if (value == null) return null;
    final s = value.trim();
    if (s.isEmpty) return null;
    return s.length > _maxDetailLength
        ? '${s.substring(0, _maxDetailLength)}…'
        : s;
  }
}
