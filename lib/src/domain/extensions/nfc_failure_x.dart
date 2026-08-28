import '../enums/nfc_failure_type.dart';

/// Message mặc định (tiếng Việt) + khả năng thử lại cho từng loại lỗi.
/// App tiêu thụ có nhu cầu i18n nên tự viết bảng tra cứu tương đương thay vì
/// dùng trực tiếp `displayMessage` — bảng này chỉ để tiện dùng ngay/tham khảo.
extension NfcFailurePresentation on NfcFailureType {
  String get displayMessage => switch (this) {
        NfcFailureType.timeout => 'Không tìm thấy thẻ, vui lòng thử lại',
        NfcFailureType.tagLost =>
          'Mất kết nối với thẻ, vui lòng giữ yên thẻ và thử lại',
        NfcFailureType.nfcDisabled => 'NFC đang tắt',
        NfcFailureType.wrongCan => 'Mã CAN không đúng, vui lòng kiểm tra lại',
        NfcFailureType.paceFailed =>
          'Không thiết lập được phiên đọc an toàn với thẻ',
        NfcFailureType.bacFailed => 'Không đọc được giấy tờ này qua BAC',
        NfcFailureType.dgMissing => 'Thẻ thiếu dữ liệu cần thiết',
        NfcFailureType.activeAuthFailed => 'Xác thực chip thất bại',
        NfcFailureType.unknown => 'Có lỗi xảy ra, vui lòng thử lại',
      };

  /// true = nên cho người dùng bấm "Thử lại" ngay; false = lỗi cấu hình/nghiệp
  /// vụ, nên dừng lại (đổi phương thức, quay lại màn trước...).
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
