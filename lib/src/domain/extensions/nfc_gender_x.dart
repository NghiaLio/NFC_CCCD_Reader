import '../enums/nfc_gender.dart';

/// Nhãn hiển thị tiếng Việt cho [NfcGender]. App tiêu thụ có nhu cầu i18n nên
/// tự viết bảng tra cứu tương đương thay vì dùng trực tiếp `label`.
extension NfcGenderPresentation on NfcGender {
  String get label => switch (this) {
        NfcGender.male => 'Nam',
        NfcGender.female => 'Nữ',
        NfcGender.unspecified => 'Không xác định',
      };
}
