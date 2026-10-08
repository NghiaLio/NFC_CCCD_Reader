import '../enums/nfc_read_stage.dart';

/// Chi tiết kỹ thuật của 1 `NfcFailure` — metadata từ tầng native/giao thức,
/// **không phải** thông điệp hiển thị và **không chứa PII**.
///
/// App dùng các trường này để log chẩn đoán (Sentry/Crashlytics) và tự map
/// `NfcFailureType` sang thông điệp cho người dùng.
class NfcErrorDetails {
  /// Byte 1 của status word APDU gây lỗi (nếu có).
  final int? sw1;

  /// Byte 2 của status word APDU gây lỗi (nếu có).
  final int? sw2;

  /// Mốc thô đang thực hiện khi lỗi xảy ra.
  final NfcReadStage? stage;

  /// Tên class/type của lỗi GỐC từ dmrtd/native (ví dụ `'PACEError'`,
  /// `'ComProviderError'`, `'PassportError'`). Dùng để truy vết, không lộ PII.
  final String? rootCause;

  /// Chi tiết kỹ thuật ĐÃ SANITIZE (không PII) — ví dụ mã giao thức, không phải
  /// nội dung dữ liệu thẻ.
  final String? detail;

  const NfcErrorDetails({
    this.sw1,
    this.sw2,
    this.stage,
    this.rootCause,
    this.detail,
  });

  @override
  String toString() => 'NfcErrorDetails('
      '${sw1 != null ? 'sw: ${_hex(sw1!)}${sw2 != null ? _hex(sw2!) : ""} ' : ""}'
      '${stage != null ? 'stage: $stage ' : ""}'
      '${rootCause != null ? 'rootCause: $rootCause ' : ""}'
      '${detail != null ? 'detail: $detail' : ""})';

  static String _hex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
}
