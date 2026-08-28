import 'package:dmrtd/dmrtd.dart';

import '../../domain/entities/nfc_failure.dart';
import '../../domain/enums/nfc_failure_type.dart';

/// Map exception từ dmrtd sang [NfcFailure]. Tách riêng khỏi service đọc chip
/// để test được logic phân loại KHÔNG CẦN thiết bị NFC thật — đây là vùng đã
/// gây 3 bug thật trong quá trình phát triển bản gốc (xem comment từng
/// nhánh bên dưới), chỉ phát hiện được qua test thiết bị vì trước đó không
/// có unit test cho phần này.
class NfcErrorClassifier {
  const NfcErrorClassifier._();

  static const _tagLostMessage = 'Mất kết nối với thẻ giữa chừng';

  static NfcFailure tagLost() =>
      const NfcFailure(NfcFailureType.tagLost, message: _tagLostMessage);

  static NfcFailure fromPassportError(PassportError e) {
    if (_isAuthFailedStatus(e)) {
      return const NfcFailure(NfcFailureType.wrongCan);
    }
    if (isTagLostError(e)) return tagLost();
    return NfcFailure(NfcFailureType.paceFailed, message: e.message);
  }

  /// BUG THẬT #1 đã gặp: khi CAN sai, dmrtd KHÔNG ném `PassportError` như
  /// dartdoc mô tả, mà ném `PACEError` ("Auth token from ICC and terminal
  /// are not the same") — 1 nhóm exception PACE riêng, ném thẳng từ
  /// `PACE.initSession`, không đi qua lớp bọc `PassportError` thông thường,
  /// và cũng KHÔNG được dmrtd export public (giống tình huống `CanKey`).
  /// Nếu chỉ bắt `on PassportError`, lỗi này thoát ra ngoài dạng chưa xác
  /// định → bị nuốt hoàn toàn ở tầng gọi, người dùng không thấy thông báo gì.
  /// Đây là catch-all cuối chuỗi: tới được điểm gọi hàm này nghĩa là đã đọc
  /// EF.CardAccess thành công, nên lỗi PACE còn lại gần như luôn là CAN sai.
  static NfcFailure fromGenericException(Object e) {
    // BUG THẬT #2 đã gặp: catch-all ở trên có lỗ hổng — MỌI bước PACE trong
    // dmrtd (step 0-4 và wrapper ngoài cùng) đều tự bọc
    // `try { ... } on Exception catch (e) { throw PACEError("...: $e"); }`
    // quanh chính transceive APDU. Nếu rút thẻ giữa lúc đang trao đổi APDU
    // trong PACE, lỗi mất kết nối thật (`ComProviderError`/`NfcProviderError`)
    // bị chính dmrtd bắt và ném lại thành `PACEError`, xoá mất type gốc.
    // Giả định "tới bước PACE thì lỗi còn lại luôn là CAN sai" SAI trong
    // trường hợp này. Giải pháp: `$e` trong dmrtd nội suy chuỗi lỗi gốc vào
    // message, nên `PACEError.toString()` vẫn còn chứa TÊN CLASS gốc dù đã
    // bị bọc — dùng string-match tên class (không phải mã lỗi giao thức thô)
    // để khôi phục đúng type trước khi map.
    if (isTagLostError(e)) return tagLost();
    return NfcFailure(NfcFailureType.wrongCan, message: e.toString());
  }

  // sw=6300 = PACE auth token mismatch (sai CAN) — status word ISO 7816,
  // so trực tiếp field public thay vì string-match, vì `StatusWord` cũng
  // không được dmrtd export public.
  static bool _isAuthFailedStatus(PassportError e) {
    final code = e.code;
    return code != null && code.sw1 == 0x63 && code.sw2 == 0x00;
  }

  /// BUG THẬT #3 đã gặp: ban đầu chỉ kiểm tra `e is ComProviderError`, không
  /// tính tới việc dmrtd bọc lỗi mất kết nối vào exception khác (xem
  /// [fromGenericException]) — chỉ còn thấy tên class gốc qua nội suy chuỗi
  /// trong message, không phải string-match mã lỗi giao thức thô.
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
}
