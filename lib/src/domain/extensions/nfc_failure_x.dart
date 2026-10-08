import '../enums/nfc_failure_type.dart';

/// Helper hành vi (KHÔNG phải string hiển thị) cho từng [NfcFailureType].
///
/// App tự map [NfcFailureType] sang thông điệp ngôn ngữ riêng — lib không kèm
/// string UI. [isRecoverable] chỉ là gợi ý hành vi: có nên cho người dùng bấm
/// "Thử lại" ngay hay dừng lại.
extension NfcFailureBehavior on NfcFailureType {
  /// true = nên cho người dùng thử lại ngay (lỗi tạm thời); false = lỗi cấu
  /// hình/nghiệp vụ, nên dừng lại (đổi phương thức, quay lại màn trước...).
  bool get isRecoverable => switch (this) {
        NfcFailureType.timeout ||
        NfcFailureType.tagLost ||
        NfcFailureType.wrongCan ||
        NfcFailureType.paceFailed ||
        NfcFailureType.activeAuthFailed ||
        NfcFailureType.unknown =>
          true,
        NfcFailureType.nfcDisabled ||
        NfcFailureType.bacFailed ||
        NfcFailureType.dgMissing =>
          false,
      };
}
