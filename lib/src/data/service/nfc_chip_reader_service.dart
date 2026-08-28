import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dmrtd/dmrtd.dart';

import '../../domain/entities/nfc_failure.dart';
import '../../domain/entities/nfc_read_input.dart';
import '../../domain/entities/nfc_read_result.dart';
import '../../domain/enums/aa_evidence_status.dart';
import '../../domain/enums/nfc_failure_type.dart';
import '../../domain/enums/nfc_gender.dart';
import '../../domain/enums/nfc_read_stage.dart';
import '../../domain/enums/nfc_session_mode.dart';
import '../parser/nfc_dg13_parser.dart';
import 'can_key_adapter.dart';
import 'nfc_error_classifier.dart';

typedef _Identity = ({
  String? idNumber,
  String? fullName,
  DateTime? dateOfBirth,
  DateTime? dateOfExpiry,
  NfcGender? gender,
  String? nationality,
});

typedef _AaEvidence = ({
  Uint8List? challenge,
  Uint8List? signature,
  Uint8List? publicKeyBytes,
  String? algorithm,
  AaEvidenceStatus status,
});

/// Đọc 1 phiên chip MRTD: connect → PACE/BAC → EF.COM → DG1/DG2/DG13/DG15+AA,
/// tất cả trong cùng 1 lần chạm thẻ.
///
/// [logSink] tuỳ chọn — package không tự phụ thuộc bất kỳ logger cụ thể nào
/// (app tiêu thụ có thể dùng Sentry/logger riêng); chỉ nhận message đã được
/// rút gọn/ẩn danh sẵn (fingerprint SHA-256, không phải giá trị PII thật).
class NfcChipReaderService {
  NfcChipReaderService({
    NfcProvider? nfcProvider,
    this.connectTimeout = const Duration(seconds: 20),
    void Function(String message)? logSink,
  })  : _nfcProvider = nfcProvider ?? NfcProvider(),
        _logSink = logSink;

  final NfcProvider _nfcProvider;
  final Duration connectTimeout;
  final void Function(String message)? _logSink;

  Future<NfcReadResult> read(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
  }) async {
    try {
      onStage?.call(NfcReadStage.waitingForCard);
      try {
        await _nfcProvider.connect(timeout: connectTimeout);
      } on NfcProviderError {
        throw const NfcFailure(
          NfcFailureType.timeout,
          message: 'Không tìm thấy thẻ trong thời gian chờ',
        );
      }

      // connect() của flutter_nfc_kit tự disconnect và return LẶNG LẼ nếu tag
      // không phải ISO-7816 (không throw) — phải tự kiểm tra isConnected().
      if (!_nfcProvider.isConnected()) {
        throw const NfcFailure(
          NfcFailureType.timeout,
          message: 'Tag không hỗ trợ (không phải ISO-7816)',
        );
      }

      onStage?.call(NfcReadStage.authenticating);
      final passport = Passport(_nfcProvider);
      final efCom = await _authenticateAndReadEfCom(passport, input);
      onStage?.call(NfcReadStage.reading);
      final result = await _readDeclaredDataGroups(passport, efCom);
      onStage?.call(NfcReadStage.validating);
      return result;
    } on NfcFailure {
      rethrow;
    } catch (e) {
      if (NfcErrorClassifier.isTagLostError(e)) {
        throw NfcErrorClassifier.tagLost();
      }
      throw NfcFailure(NfcFailureType.unknown, message: e.toString());
    } finally {
      await _nfcProvider.disconnect();
    }
  }

  /// Huỷ phiên đang chạy — ngắt kết nối khiến `read()` tự thoát qua nhánh lỗi.
  Future<void> cancel() => _nfcProvider.disconnect();

  Future<EfCOM> _authenticateAndReadEfCom(
    Passport passport,
    NfcReadInput input,
  ) async {
    try {
      switch (input.mode) {
        case NfcSessionMode.pace:
          final efCardAccess = await passport.readEfCardAccess();
          final accessKey = buildCanAccessKey(input.can!);
          await passport.startSessionPACE(accessKey, efCardAccess);
        case NfcSessionMode.bac:
          // v1: BAC chưa triển khai đầy đủ — mở rộng ở đây khi có giấy tờ
          // quốc tế thật để test (dùng DBAKey + passport.startSession()).
          throw const NfcFailure(
            NfcFailureType.bacFailed,
            message: 'BAC chưa được hỗ trợ',
          );
      }
      return await passport.readEfCOM();
    } on NfcFailure {
      rethrow;
    } on PassportError catch (e) {
      _logSink?.call(
        'PACE PassportError: sw1=${e.code?.sw1.toRadixString(16)} '
        'sw2=${e.code?.sw2.toRadixString(16)}',
      );
      throw NfcErrorClassifier.fromPassportError(e);
    } on Exception catch (e) {
      throw NfcErrorClassifier.fromGenericException(e);
    }
  }

  Future<NfcReadResult> _readDeclaredDataGroups(
    Passport passport,
    EfCOM efCom,
  ) async {
    final warnings = <String>[];
    final identity = await _readIdentity(passport, efCom, warnings);
    final faceImageBytes = await _readFaceImage(passport, efCom, warnings);
    final extendedData = await _readExtendedData(passport, efCom, warnings);
    final aa = await _readAaEvidence(passport, efCom, warnings);

    return NfcReadResult(
      idNumber: identity.idNumber,
      fullName: identity.fullName,
      dateOfBirth: identity.dateOfBirth,
      dateOfExpiry: identity.dateOfExpiry,
      gender: identity.gender,
      nationality: identity.nationality,
      faceImageBytes: faceImageBytes,
      extendedData: extendedData,
      aaChallenge: aa.challenge,
      aaSignature: aa.signature,
      aaPublicKeyBytes: aa.publicKeyBytes,
      aaAlgorithm: aa.algorithm,
      aaStatus: aa.status,
      // Passive Authentication ngoài phạm vi v1 — luôn false.
      isChipAuthenticityVerified: false,
      warnings: warnings,
    );
  }

  Future<_Identity> _readIdentity(
    Passport passport,
    EfCOM efCom,
    List<String> warnings,
  ) async {
    if (!efCom.dgTags.contains(EfDG1.TAG)) {
      warnings.add('Thẻ không công bố DG1 (MRZ)');
      return (
        idNumber: null,
        fullName: null,
        dateOfBirth: null,
        dateOfExpiry: null,
        gender: null,
        nationality: null,
      );
    }
    try {
      final mrz = (await passport.readEfDG1()).mrz;
      final fullName = '${mrz.firstName} ${mrz.lastName}'.trim();
      // CCCD Việt Nam dùng MRZ chuẩn TD1: số định danh nằm ở 12 ký tự đầu
      // của optionalData, KHÔNG phải documentNumber.
      final optionalData = mrz.optionalData;
      final idNumber =
          optionalData.length >= 12 ? optionalData.substring(0, 12) : null;
      if (idNumber == null) {
        warnings.add('Không đọc được số định danh từ MRZ (DG1)');
      }
      return (
        idNumber: idNumber,
        fullName: fullName.isEmpty ? null : fullName,
        dateOfBirth: mrz.dateOfBirth,
        dateOfExpiry: mrz.dateOfExpiry,
        gender: _parseGender(mrz.gender),
        nationality: mrz.nationality,
      );
    } catch (e) {
      if (NfcErrorClassifier.isTagLostError(e)) {
        throw NfcErrorClassifier.tagLost();
      }
      warnings.add('Không đọc được DG1 (MRZ) dù thẻ có công bố');
      return (
        idNumber: null,
        fullName: null,
        dateOfBirth: null,
        dateOfExpiry: null,
        gender: null,
        nationality: null,
      );
    }
  }

  Future<Uint8List?> _readFaceImage(
    Passport passport,
    EfCOM efCom,
    List<String> warnings,
  ) async {
    if (!efCom.dgTags.contains(EfDG2.TAG)) {
      warnings.add('Thẻ không công bố DG2 (ảnh)');
      return null;
    }
    try {
      // dmrtd tự parse cấu trúc TLV/biometric-data-block của DG2 — KHÔNG tự
      // cắt base64 thủ công.
      final imageData = (await passport.readEfDG2()).imageData;
      if (imageData == null) warnings.add('DG2 không có dữ liệu ảnh');
      return imageData;
    } catch (e) {
      if (NfcErrorClassifier.isTagLostError(e)) {
        throw NfcErrorClassifier.tagLost();
      }
      warnings.add('Không đọc được DG2 (ảnh) dù thẻ có công bố');
      return null;
    }
  }

  Future<Map<String, String>?> _readExtendedData(
    Passport passport,
    EfCOM efCom,
    List<String> warnings,
  ) async {
    if (!efCom.dgTags.contains(EfDG13.TAG)) return null;
    try {
      final rawBytes = (await passport.readEfDG13()).toBytes();
      final extendedData = NfcDg13Parser.parse(rawBytes);
      if (extendedData.isEmpty) {
        warnings.add('DG13 không có field nào đọc được');
      }
      return extendedData;
    } catch (e) {
      if (NfcErrorClassifier.isTagLostError(e)) {
        throw NfcErrorClassifier.tagLost();
      }
      // Không nội suy nội dung exception vào warning — DG13 chứa PII mở rộng,
      // message exception thô có thể vô tình lộ dữ liệu.
      warnings.add('Không đọc được/parse được DG13 dù thẻ có công bố');
      return null;
    }
  }

  Future<_AaEvidence> _readAaEvidence(
    Passport passport,
    EfCOM efCom,
    List<String> warnings,
  ) async {
    if (!efCom.dgTags.contains(EfDG15.TAG)) {
      return (
        challenge: null,
        signature: null,
        publicKeyBytes: null,
        algorithm: null,
        status: AaEvidenceStatus.notSupported,
      );
    }
    try {
      final dg15 = await passport.readEfDG15();
      // Challenge PHẢI là nonce CSPRNG mới mỗi phiên — KHÔNG được cố định
      // (chống replay chữ ký từ 1 lần quét trước).
      final challenge = _generateAaChallenge();
      final signature = await passport.activeAuthenticate(challenge);
      _logSink?.call(
        'AA evidence captured — fingerprint: '
        'challenge=${_fingerprint(challenge)} signature=${_fingerprint(signature)}',
      );
      return (
        challenge: challenge,
        signature: signature,
        publicKeyBytes: dg15.aaPublicKey.rawSubjectPublicKey(),
        algorithm: _describeAaAlgorithm(dg15.aaPublicKey.type),
        status: AaEvidenceStatus.captured,
      );
    } catch (e) {
      if (NfcErrorClassifier.isTagLostError(e)) {
        throw NfcErrorClassifier.tagLost();
      }
      warnings.add('Không lấy được bằng chứng Active Authentication (AA)');
      return (
        challenge: null,
        signature: null,
        publicKeyBytes: null,
        algorithm: null,
        status: AaEvidenceStatus.failed,
      );
    }
  }

  Uint8List _generateAaChallenge() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(Passport.aaChallengeLen, (_) => random.nextInt(256)),
    );
  }

  // Fingerprint 1 chiều CHỈ để đối chiếu 2 lần quét khác nhau (chống replay)
  // trong log chẩn đoán — KHÔNG BAO GIỜ log challenge/signature thật.
  String _fingerprint(Uint8List bytes) =>
      crypto.sha256.convert(bytes).toString().substring(0, 12);

  String _describeAaAlgorithm(AAPublicKeyType type) => switch (type) {
        AAPublicKeyType.RSA => 'RSA',
        AAPublicKeyType.ECC => 'EC',
      };

  // MRZ mã hoá giới tính bằng 1 ký tự ICAO: 'M', 'F', hoặc '<' (không khai
  // báo). Chuẩn hoá về enum thay vì để nguyên ký tự thô cho tầng gọi.
  NfcGender _parseGender(String mrzGender) => switch (mrzGender) {
        'M' => NfcGender.male,
        'F' => NfcGender.female,
        _ => NfcGender.unspecified,
      };
}
