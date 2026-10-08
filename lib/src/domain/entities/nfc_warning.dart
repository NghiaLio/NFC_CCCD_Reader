import '../enums/nfc_warning_type.dart';

/// 1 cảnh báo không-fatal, dạng cấu trúc (không kèm string hiển thị).
///
/// App dùng [type] để map sang thông điệp ngôn ngữ riêng. [detail] (tuỳ chọn)
/// là chi tiết kỹ thuật ĐÃ SANITIZE — không chứa PII.
class NfcWarning {
  final NfcWarningType type;

  /// Chi tiết kỹ thuật tuỳ chọn (không PII). Thường để null.
  final String? detail;

  const NfcWarning(this.type, {this.detail});

  @override
  String toString() =>
      'NfcWarning(${type.name}${detail != null ? ', $detail' : ''})';
}
