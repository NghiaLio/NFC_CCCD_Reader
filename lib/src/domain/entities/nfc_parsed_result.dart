import 'dart:typed_data';

import 'nfc_raw_result.dart';
import 'nfc_warning.dart';
import '../enums/aa_evidence_status.dart';
import '../enums/nfc_gender.dart';

/// Kết quả đọc và phân tích cú pháp (parsed) chip MRTD / CCCD Việt Nam thành
/// các thông tin nhân thân có cấu trúc.
///
/// Toàn bộ trường dữ liệu thẻ đều là nullable vì phụ thuộc vào các Data Group
/// thực tế thẻ công bố.
///
/// **Không kèm string hiển thị**: app tự map enum/mã (ví dụ [gender],
/// [nationality], [NfcWarning.type]) sang ngôn ngữ riêng.
class NfcParsedResult {
  /// ID phiên đọc — chung với mọi `NfcTraceEvent` của lượt quét này, dùng để
  /// nhóm log trong hệ thống phía trên.
  final String sessionId;

  /// Số định danh cá nhân / Số CCCD từ DG1/MRZ.
  final String? idNumber;

  /// Họ và tên không dấu (chuẩn ICAO) từ DG1/MRZ.
  final String? fullName;

  /// Tên đầy đủ **có dấu** (nguồn DG13 field 2) — ví dụ "NGUYỄN VĂN ANH".
  /// Fallback về [fullName] (MRZ, không dấu) khi DG13 không cung cấp.
  final String? fullNameWithDiacritics;

  /// Ngày sinh.
  final DateTime? dateOfBirth;

  /// Ngày hết hạn thẻ.
  final DateTime? dateOfExpiry;

  /// Giới tính đã chuẩn hóa enum.
  final NfcGender? gender;

  /// Mã quốc tịch ICAO alpha-3 (VD: `'VNM'`).
  final String? nationality;

  /// Dữ liệu ảnh khuôn mặt từ DG2.
  final Uint8List? faceImageBytes;

  /// Dữ liệu mở rộng từ DG13 (đặc thù CCCD Việt Nam): quê quán, nơi thường
  /// trú, dân tộc, tôn giáo, cha/mẹ/vợ-chồng... Key tiếng Anh.
  final Map<String, String>? extendedData;

  /// Nonce CSPRNG đã gửi cho chip trong Active Authentication.
  final Uint8List? aaChallenge;

  /// Giá trị chữ ký số trả về từ `activeAuthenticate(aaChallenge)` của chip.
  final Uint8List? aaSignature;

  /// SubjectPublicKey từ DG15 — dùng để bên thứ 3 (thường là backend) verify [aaSignature].
  final Uint8List? aaPublicKeyBytes;

  /// 'RSA' hoặc 'EC' — thuật toán khoá công khai DG15.
  final String? aaAlgorithm;

  /// Trạng thái Active Authentication.
  final AaEvidenceStatus aaStatus;

  /// Passive Authentication (verify SOD/chuỗi CSCA) KHÔNG được thực hiện ở client — luôn `false`.
  final bool isChipAuthenticityVerified;

  /// Cảnh báo không-fatal trong quá trình đọc chip.
  final List<NfcWarning> warnings;

  /// Dữ liệu thô (raw bytes / Base64) thu được trong cùng 1 lần chạm thẻ này.
  /// Giúp lấy cả dữ liệu hiển thị lẫn payload gửi Backend mà không cần quét thẻ lần 2.
  final NfcRawResult? raw;

  const NfcParsedResult({
    required this.sessionId,
    this.idNumber,
    this.fullName,
    this.fullNameWithDiacritics,
    this.dateOfBirth,
    this.dateOfExpiry,
    this.gender,
    this.nationality,
    this.faceImageBytes,
    this.extendedData,
    this.aaChallenge,
    this.aaSignature,
    this.aaPublicKeyBytes,
    this.aaAlgorithm,
    this.aaStatus = AaEvidenceStatus.notSupported,
    this.isChipAuthenticityVerified = false,
    this.warnings = const [],
    this.raw,
  });
}

/// Alias cũ tương thích ngược. Khuyến nghị dùng [NfcParsedResult] để phân biệt rõ với [NfcRawResult].
@Deprecated('Sử dụng NfcParsedResult để phân biệt rõ với NfcRawResult')
typedef NfcReadResult = NfcParsedResult;

