import '../enums/nfc_session_mode.dart';

/// Input cho 1 phiên đọc chip MRTD: PACE (CAN 6 số, CCCD Việt Nam) hoặc BAC
/// (document number + DOB + DOE, cho giấy tờ quốc tế). Không có giá trị mặc
/// định nào nguy hiểm — chỉ tạo được từ dữ liệu người dùng nhập, factory
/// throw ngay nếu input không hợp lệ (fail fast tại boundary).
///
/// Validation lỗi ném `ArgumentError` mang **tên trường lỗi** qua `.name`
/// (`can`, `cccdNumber`, `documentNumber`). Package không kèm thông điệp UI —
/// app tự map `.name` sang thông điệp bằng ngôn ngữ riêng.
class NfcReadInput {
  final NfcSessionMode mode;
  final String? can;
  final String? documentNumber;
  final DateTime? dateOfBirth;
  final DateTime? dateOfExpiry;

  const NfcReadInput._({
    required this.mode,
    this.can,
    this.documentNumber,
    this.dateOfBirth,
    this.dateOfExpiry,
  });

  factory NfcReadInput.pace({required String can}) {
    if (!isValidCan(can)) {
      throw ArgumentError.value(can, 'can');
    }
    return NfcReadInput._(mode: NfcSessionMode.pace, can: can);
  }

  /// CCCD Việt Nam gắn chip không in riêng mã CAN như hộ chiếu — quy ước CAN
  /// dùng cho PACE là **6 số cuối của số CCCD** (12 số). Factory này để người
  /// dùng nhập đúng thứ họ có sẵn (số CCCD) thay vì phải tự tách 6 số cuối.
  factory NfcReadInput.paceFromCccdNumber(String cccdNumber) {
    if (!isValidCccdNumber(cccdNumber)) {
      throw ArgumentError.value(cccdNumber, 'cccdNumber');
    }
    return NfcReadInput.pace(can: cccdNumber.substring(cccdNumber.length - 6));
  }

  factory NfcReadInput.bac({
    required String documentNumber,
    required DateTime dateOfBirth,
    required DateTime dateOfExpiry,
  }) {
    if (documentNumber.trim().isEmpty) {
      throw ArgumentError.value(documentNumber, 'documentNumber');
    }
    return NfcReadInput._(
      mode: NfcSessionMode.bac,
      documentNumber: documentNumber,
      dateOfBirth: dateOfBirth,
      dateOfExpiry: dateOfExpiry,
    );
  }

  static bool isValidCan(String value) => RegExp(r'^\d{6}$').hasMatch(value);

  static bool isValidCccdNumber(String value) =>
      RegExp(r'^\d{12}$').hasMatch(value);

  /// Không in giá trị CAN/document number thật ra log — chỉ in mode.
  @override
  String toString() => 'NfcReadInput(mode: $mode)';
}
