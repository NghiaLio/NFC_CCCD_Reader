import '../enums/nfc_failure_type.dart';

/// Mọi exception từ luồng đọc chip phải map về đúng 1 [NfcFailureType] ngay
/// tại nơi bắt (`NfcErrorClassifier`) — phần còn lại của app chỉ xử lý theo
/// `type`, không bao giờ string-match message.
class NfcFailure implements Exception {
  final NfcFailureType type;
  final String? message;

  const NfcFailure(this.type, {this.message});

  @override
  String toString() =>
      'NfcFailure(type: $type${message != null ? ', message: $message' : ''})';
}
