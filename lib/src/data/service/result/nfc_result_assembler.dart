import 'dart:typed_data';

import '../../../domain/entities/nfc_parsed_result.dart';
import '../../../domain/entities/nfc_raw_result.dart';
import '../../../domain/entities/nfc_warning.dart';
import '../../../domain/enums/aa_evidence_status.dart';
import '../../../domain/enums/nfc_gender.dart';

/// Dữ liệu thông tin nhân thân trích xuất từ DG1.
typedef CardIdentity = ({
  String? idNumber,
  String? fullName,
  DateTime? dateOfBirth,
  DateTime? dateOfExpiry,
  NfcGender? gender,
  String? nationality,
});

/// Dữ liệu mở rộng CCCD Việt Nam trích xuất từ DG13.
typedef Dg13Data = ({Map<String, String>? data, String? fullName});

/// Bằng chứng xác thực chủ động (Active Authentication) từ DG15.
typedef AaResult = ({
  Uint8List? dg15Bytes,
  Uint8List? challenge,
  Uint8List? signature,
  Uint8List? publicKeyBytes,
  String? algorithm,
  AaEvidenceStatus status,
});

/// Lắp ghép dữ liệu từ các Data Group thành cặp đối tượng kết quả
/// [NfcParsedResult] và [NfcRawResult] có liên kết 2 chiều.
class NfcResultAssembler {
  const NfcResultAssembler._();

  static ({NfcParsedResult parsed, NfcRawResult raw}) assemble({
    required String sessionId,
    required CardIdentity identity,
    required Uint8List? dg1Bytes,
    required Uint8List? dg2Bytes,
    required Uint8List? faceImageBytes,
    required Uint8List? dg13Bytes,
    required Dg13Data dg13Data,
    required Uint8List? dg14Bytes,
    required AaResult aaResult,
    required Uint8List? sodBytes,
    required Uint8List comBytes,
    required List<NfcWarning> warnings,
  }) {
    final baseRawResult = NfcRawResult.fromBytes(
      sessionId: sessionId,
      dg1Bytes: dg1Bytes,
      sodBytes: sodBytes,
      dg13Bytes: dg13Bytes,
      dg2Bytes: dg2Bytes,
      dg14Bytes: dg14Bytes,
      dg15Bytes: aaResult.dg15Bytes,
      comBytes: comBytes,
      aaChallenge: aaResult.challenge,
      aaSignature: aaResult.signature,
      aaStatus: aaResult.status,
      warnings: warnings,
    );

    final parsedResult = NfcParsedResult(
      sessionId: sessionId,
      idNumber: identity.idNumber,
      fullName: identity.fullName,
      fullNameWithDiacritics: dg13Data.fullName ?? identity.fullName,
      dateOfBirth: identity.dateOfBirth,
      dateOfExpiry: identity.dateOfExpiry,
      gender: identity.gender,
      nationality: identity.nationality,
      faceImageBytes: faceImageBytes,
      extendedData: dg13Data.data,
      aaChallenge: aaResult.challenge,
      aaSignature: aaResult.signature,
      aaPublicKeyBytes: aaResult.publicKeyBytes,
      aaAlgorithm: aaResult.algorithm,
      aaStatus: aaResult.status,
      isChipAuthenticityVerified: false,
      warnings: warnings,
      raw: baseRawResult,
    );

    final rawResult = baseRawResult.copyWith(parsed: parsedResult);
    return (parsed: parsedResult, raw: rawResult);
  }
}
