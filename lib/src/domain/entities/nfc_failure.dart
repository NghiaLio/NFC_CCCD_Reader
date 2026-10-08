import 'nfc_error_details.dart';
import '../enums/nfc_failure_type.dart';

/// Mọi exception từ luồng đọc chip phải map về đúng 1 [NfcFailureType] ngay tại
/// nơi bắt (`NfcErrorClassifier`) — app chỉ xử lý theo [type] + [errorDetails]
/// (metadata), không bao giờ string-match.
///
/// **Không kèm thông điệp hiển thị**: app tự map [type] sang thông điệp ngôn
/// ngữ riêng; [errorDetails] chỉ là metadata kỹ thuật (SW1/SW2, root cause, chi
/// tiết đã sanitize) để log chẩn đoán.
class NfcFailure implements Exception {
  final NfcFailureType type;

  /// ID phiên đọc mà lỗi này xảy ra trong — chung với mọi `NfcTraceEvent` của
  /// lượt quét đó, để nhóm log trong hệ thống phía trên.
  final String? sessionId;

  /// Metadata kỹ thuật từ native/giao thức — không phải string hiển thị,
  /// không chứa PII.
  final NfcErrorDetails? errorDetails;

  const NfcFailure(this.type, {this.sessionId, this.errorDetails});

  @override
  String toString() => 'NfcFailure(type: $type'
      '${sessionId != null ? ', sessionId: $sessionId' : ''}'
      '${errorDetails != null ? ', details: $errorDetails' : ''})';
}
