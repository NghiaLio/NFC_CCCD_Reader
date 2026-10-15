import 'dart:convert';
import 'dart:typed_data';

import 'nfc_parsed_result.dart';
import 'nfc_warning.dart';
import '../enums/aa_evidence_status.dart';

/// Kết quả đọc thuần dữ liệu thô (raw bytes / chuỗi Base64) của các Data Group
/// và file bảo mật trên chip MRTD / CCCD Việt Nam.
///
/// Phục vụ cho việc gửi payload lên Backend để thực hiện xác thực tính toàn vẹn,
/// Passive Authentication (xác minh chữ ký SOD với chứng thư số CSCA CA root),
/// và Active Authentication (verify chữ ký AA với khóa công khai trong DG15).
class NfcRawResult {
  /// ID phiên đọc — dùng để nhóm trace log.
  final String sessionId;

  /// Chuỗi Base64 raw bytes của DG1 (MRZ).
  final String? dg1;

  /// Chuỗi Base64 raw bytes của EF.SOD (Document Security Object - chứa chữ ký
  /// của cơ quan phát hành thẻ C06/BCA).
  final String? sod;

  /// Chuỗi Base64 raw bytes của DG13 (dữ liệu mở rộng CCCD Việt Nam).
  final String? dg13;

  /// Chuỗi Base64 raw bytes của DG2 (ảnh sinh trắc học khuôn mặt).
  final String? dg2;

  /// Chuỗi Base64 raw bytes của DG14 (Security Infos).
  final String? dg14;

  /// Chuỗi Base64 raw bytes của DG15 (Active Authentication Public Key Info).
  final String? dg15;

  /// Chuỗi Base64 raw bytes của EF.COM (Common Data - danh sách Data Group có trên thẻ).
  final String? com;

  /// Dữ liệu byte gốc của DG1.
  final Uint8List? dg1Bytes;

  /// Dữ liệu byte gốc của EF.SOD.
  final Uint8List? sodBytes;

  /// Dữ liệu byte gốc của DG13.
  final Uint8List? dg13Bytes;

  /// Dữ liệu byte gốc của DG2.
  final Uint8List? dg2Bytes;

  /// Dữ liệu byte gốc của DG14.
  final Uint8List? dg14Bytes;

  /// Dữ liệu byte gốc của DG15.
  final Uint8List? dg15Bytes;

  /// Dữ liệu byte gốc của EF.COM.
  final Uint8List? comBytes;

  /// Nonce CSPRNG đã gửi cho chip trong Active Authentication.
  final Uint8List? aaChallenge;

  /// Chữ ký phản hồi từ chip qua `activeAuthenticate(aaChallenge)`.
  final Uint8List? aaSignature;

  /// Trạng thái Active Authentication.
  final AaEvidenceStatus aaStatus;

  /// Cảnh báo không-fatal trong quá trình đọc chip.
  final List<NfcWarning> warnings;

  /// Kết quả đã phân tích cú pháp (parsed) thu được trong cùng 1 lần chạm thẻ này.
  /// Giúp lấy cả thông tin hiển thị UI lẫn raw bytes mà không cần quét thẻ 2 lần.
  final NfcParsedResult? parsed;

  const NfcRawResult({
    required this.sessionId,
    this.dg1,
    this.sod,
    this.dg13,
    this.dg2,
    this.dg14,
    this.dg15,
    this.com,
    this.dg1Bytes,
    this.sodBytes,
    this.dg13Bytes,
    this.dg2Bytes,
    this.dg14Bytes,
    this.dg15Bytes,
    this.comBytes,
    this.aaChallenge,
    this.aaSignature,
    this.aaStatus = AaEvidenceStatus.notSupported,
    this.warnings = const [],
    this.parsed,
  });

  /// Khởi tạo [NfcRawResult] từ các mảng byte gốc, tự động mã hóa Base64
  /// cho các trường string tương ứng (`dg1`, `sod`, `dg13`, `dg2`, `dg14`, `dg15`, `com`).
  factory NfcRawResult.fromBytes({
    required String sessionId,
    Uint8List? dg1Bytes,
    Uint8List? sodBytes,
    Uint8List? dg13Bytes,
    Uint8List? dg2Bytes,
    Uint8List? dg14Bytes,
    Uint8List? dg15Bytes,
    Uint8List? comBytes,
    Uint8List? aaChallenge,
    Uint8List? aaSignature,
    AaEvidenceStatus aaStatus = AaEvidenceStatus.notSupported,
    List<NfcWarning> warnings = const [],
    NfcParsedResult? parsed,
  }) {
    return NfcRawResult(
      sessionId: sessionId,
      dg1: dg1Bytes != null ? base64Encode(dg1Bytes) : null,
      sod: sodBytes != null ? base64Encode(sodBytes) : null,
      dg13: dg13Bytes != null ? base64Encode(dg13Bytes) : null,
      dg2: dg2Bytes != null ? base64Encode(dg2Bytes) : null,
      dg14: dg14Bytes != null ? base64Encode(dg14Bytes) : null,
      dg15: dg15Bytes != null ? base64Encode(dg15Bytes) : null,
      com: comBytes != null ? base64Encode(comBytes) : null,
      dg1Bytes: dg1Bytes,
      sodBytes: sodBytes,
      dg13Bytes: dg13Bytes,
      dg2Bytes: dg2Bytes,
      dg14Bytes: dg14Bytes,
      dg15Bytes: dg15Bytes,
      comBytes: comBytes,
      aaChallenge: aaChallenge,
      aaSignature: aaSignature,
      aaStatus: aaStatus,
      warnings: warnings,
      parsed: parsed,
    );
  }

  /// Trả về bản sao của [NfcRawResult] với [parsed] được gán.
  NfcRawResult copyWith({NfcParsedResult? parsed}) {
    return NfcRawResult(
      sessionId: sessionId,
      dg1: dg1,
      sod: sod,
      dg13: dg13,
      dg2: dg2,
      dg14: dg14,
      dg15: dg15,
      com: com,
      dg1Bytes: dg1Bytes,
      sodBytes: sodBytes,
      dg13Bytes: dg13Bytes,
      dg2Bytes: dg2Bytes,
      dg14Bytes: dg14Bytes,
      dg15Bytes: dg15Bytes,
      comBytes: comBytes,
      aaChallenge: aaChallenge,
      aaSignature: aaSignature,
      aaStatus: aaStatus,
      warnings: warnings,
      parsed: parsed ?? this.parsed,
    );
  }

  /// Chuỗi Base64 của [aaChallenge].
  String? get aaChallengeBase64 =>
      aaChallenge != null ? base64Encode(aaChallenge!) : null;

  /// Chuỗi Base64 của [aaSignature].
  String? get aaSignatureBase64 =>
      aaSignature != null ? base64Encode(aaSignature!) : null;

  /// Xuất dữ liệu ra Map với các key đúng theo chuẩn API FE gửi lên Backend:
  /// `dg1`, `sod`, `dg13`, `dg2`, `dg14`, `dg15`, `com`.
  Map<String, String?> toMap() => {
        'dg1': dg1,
        'sod': sod,
        'dg13': dg13,
        'dg2': dg2,
        'dg14': dg14,
        'dg15': dg15,
        'com': com,
      };

  /// Xuất dữ liệu ra Map JSON chỉ chứa các trường non-null.
  Map<String, dynamic> toJson() => {
        if (dg1 != null) 'dg1': dg1,
        if (sod != null) 'sod': sod,
        if (dg13 != null) 'dg13': dg13,
        if (dg2 != null) 'dg2': dg2,
        if (dg14 != null) 'dg14': dg14,
        if (dg15 != null) 'dg15': dg15,
        if (com != null) 'com': com,
      };

  /// Chuyển đổi sang Map dạng chuỗi Hex hoa (nếu backend yêu cầu hex thay vì base64).
  Map<String, String?> toHexMap() => {
        'dg1': dg1Bytes != null ? _toHex(dg1Bytes!) : null,
        'sod': sodBytes != null ? _toHex(sodBytes!) : null,
        'dg13': dg13Bytes != null ? _toHex(dg13Bytes!) : null,
        'dg2': dg2Bytes != null ? _toHex(dg2Bytes!) : null,
        'dg14': dg14Bytes != null ? _toHex(dg14Bytes!) : null,
        'dg15': dg15Bytes != null ? _toHex(dg15Bytes!) : null,
        'com': comBytes != null ? _toHex(comBytes!) : null,
      };

  static String _toHex(Uint8List bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join('')
      .toUpperCase();
}

