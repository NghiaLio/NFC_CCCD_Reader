import 'dart:typed_data';

import '../enums/aa_evidence_status.dart';
import '../enums/nfc_gender.dart';

/// Kết quả đọc chip MRTD — toàn bộ field nullable vì phụ thuộc Data Group
/// thực tế thẻ công bố, không phải mọi field đều luôn có.
class NfcReadResult {
  final String? idNumber;
  final String? fullName;
  final DateTime? dateOfBirth;
  final DateTime? dateOfExpiry;
  final NfcGender? gender;

  /// Mã quốc tịch ICAO alpha-3 (VD: `'VNM'`) — dùng extension
  /// `nationalityLabel` (xem `nfc_nationality_x.dart`) để lấy nhãn hiển thị.
  final String? nationality;
  final Uint8List? faceImageBytes;

  /// Dữ liệu mở rộng từ DG13 (đặc thù CCCD Việt Nam): quê quán, nơi thường
  /// trú, dân tộc, tôn giáo, cha/mẹ/vợ-chồng... Key tiếng Anh, xem
  /// [NfcDg13Parser] để biết danh sách đầy đủ. **Không lặp lại** các field đã
  /// có ở top-level (idNumber/fullName/dateOfBirth/dateOfExpiry/gender/
  /// nationality) — top-level (nguồn DG1/MRZ) là nguồn duy nhất cho các giá
  /// trị đó, tránh mơ hồ khi 2 nguồn lệch nhau.
  final Map<String, String>? extendedData;

  /// Nonce CSPRNG đã gửi cho chip trong Active Authentication — khác nhau ở
  /// mỗi lần quét (chống replay). Null nếu không capture được.
  final Uint8List? aaChallenge;

  /// Đúng giá trị trả về từ `activeAuthenticate(aaChallenge)` của chip —
  /// KHÔNG phải raw bytes DG14.
  final Uint8List? aaSignature;

  /// SubjectPublicKey từ DG15 — dùng để bên thứ 3 (thường là backend) verify
  /// [aaSignature]. Package này KHÔNG tự verify chữ ký.
  final Uint8List? aaPublicKeyBytes;

  /// 'RSA' hoặc 'EC' — thuật toán khoá công khai DG15.
  final String? aaAlgorithm;

  /// LUÔN được set tường minh — không suy luận ngầm.
  final AaEvidenceStatus aaStatus;

  /// Passive Authentication (verify SOD/chuỗi CSCA) KHÔNG được thực hiện ở
  /// v1 — luôn `false`. Không suy luận `true` chỉ vì đã đọc được EF.SOD.
  final bool isChipAuthenticityVerified;

  /// Cảnh báo không-fatal trong quá trình đọc (DG công bố nhưng đọc lỗi...).
  final List<String> warnings;

  const NfcReadResult({
    this.idNumber,
    this.fullName,
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
  });
}
