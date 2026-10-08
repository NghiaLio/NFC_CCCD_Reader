import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dmrtd/dmrtd.dart';
import 'package:dmrtd/extensions.dart';

import '../../core/nfc_constants.dart';
import '../../core/nfc_session_id.dart';
import '../../domain/entities/nfc_error_details.dart';
import '../../domain/entities/nfc_failure.dart';
import '../../domain/entities/nfc_read_input.dart';
import '../../domain/entities/nfc_read_result.dart';
import '../../domain/entities/nfc_trace_event.dart';
import '../../domain/entities/nfc_warning.dart';
import '../../domain/enums/aa_evidence_status.dart';
import '../../domain/enums/nfc_failure_type.dart';
import '../../domain/enums/nfc_gender.dart';
import '../../domain/enums/nfc_read_stage.dart';
import '../../domain/enums/nfc_session_mode.dart';
import '../../domain/enums/nfc_trace_step.dart';
import '../../domain/enums/nfc_warning_type.dart';
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
/// Mỗi phiên sinh 1 `sessionId` và phát 1 [NfcTraceEvent] breadcrumb cho từng
/// bước qua `read(onTrace: ...)` — chỉ chứa metadata an toàn (bước, SW1/SW2,
/// độ dài byte, chi tiết đã sanitize), KHÔNG kèm PII (MRZ/tên/ảnh/key). App
/// hứng stream này để log/Sentry.
class NfcChipReaderService {
  NfcChipReaderService({
    NfcProvider? nfcProvider,
    this.connectTimeout = const Duration(seconds: 20),
  }) : _nfcProvider = nfcProvider ?? NfcProvider();

  final NfcProvider _nfcProvider;
  final Duration connectTimeout;

  Future<NfcReadResult> read(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  }) async {
    final trace = _TraceSession(generateNfcSessionId(), onTrace ?? _noop);
    var stage = NfcReadStage.waitingForCard;
    try {
      trace.emit(NfcTraceStep.started);
      onStage?.call(stage);

      trace.emit(NfcTraceStep.connecting);
      try {
        await _nfcProvider.connect(timeout: connectTimeout);
      } on NfcProviderError catch (e) {
        throw NfcFailure(
          NfcFailureType.timeout,
          errorDetails: NfcErrorDetails(
            stage: stage,
            rootCause: 'NfcProviderError',
            detail: _sanitize(e.toString()),
          ),
        );
      }

      // connect() của flutter_nfc_kit tự disconnect và return LẶNG LẼ nếu tag
      // không phải ISO-7816 (không throw) — phải tự kiểm tra isConnected().
      if (!_nfcProvider.isConnected()) {
        throw const NfcFailure(
          NfcFailureType.timeout,
          errorDetails: NfcErrorDetails(
            stage: NfcReadStage.waitingForCard,
            rootCause: 'NonIso7816Tag',
          ),
        );
      }
      trace.emit(NfcTraceStep.connected);

      stage = NfcReadStage.authenticating;
      onStage?.call(stage);
      final passport = Passport(_nfcProvider);
      final efCom = await _authenticateAndReadEfCom(passport, input, trace);
      trace.emit(NfcTraceStep.sessionEstablished);

      stage = NfcReadStage.reading;
      onStage?.call(stage);
      final result = await _readDeclaredDataGroups(passport, efCom, trace);

      stage = NfcReadStage.validating;
      onStage?.call(stage);
      trace.emit(NfcTraceStep.completed);
      return result;
    } catch (e) {
      var failure = e is NfcFailure ? e : _classify(e, stage);
      // Bảo đảm mọi NfcFailure ra ngoài đều mang sessionId (để nhóm log),
      // kể cả lỗi sinh từ classifier không biết sessionId.
      if (failure.sessionId == null) {
        failure = NfcFailure(
          failure.type,
          sessionId: trace.sessionId,
          errorDetails: failure.errorDetails,
        );
      }
      final details = failure.errorDetails;
      trace.emit(
        NfcTraceStep.failed,
        sw1: details?.sw1,
        sw2: details?.sw2,
        detail: details?.rootCause ?? details?.detail,
      );
      throw failure;
    } finally {
      await _nfcProvider.disconnect();
    }
  }

  /// Huỷ phiên đang chạy — ngắt kết nối khiến `read()` tự thoát qua nhánh lỗi.
  Future<void> cancel() => _nfcProvider.disconnect();

  NfcFailure _classify(Object e, NfcReadStage stage) {
    final base = NfcErrorClassifier.isTagLostError(e)
        ? NfcErrorClassifier.tagLost(stage: stage)
        : NfcErrorClassifier.fromGenericException(e, stage: stage);
    return NfcFailure(base.type, errorDetails: base.errorDetails);
  }

  Future<EfCOM> _authenticateAndReadEfCom(
    Passport passport,
    NfcReadInput input,
    _TraceSession trace,
  ) async {
    trace.emit(NfcTraceStep.sessionStart);
    try {
      switch (input.mode) {
        case NfcSessionMode.pace:
          final efCardAccess = EfCardAccess.fromBytes(
            NfcConstants.keyAccessDataNFCIos.parseHex(),
          );
          final accessKey = buildCanAccessKey(input.can!);
          await passport.startSessionPACE(accessKey, efCardAccess);
        case NfcSessionMode.bac:
          // v1: BAC chưa triển khai đầy đủ — mở rộng ở đây khi có giấy tờ
          // quốc tế thật để test (dùng DBAKey + passport.startSession()).
          throw const NfcFailure(
            NfcFailureType.bacFailed,
            errorDetails: NfcErrorDetails(
              stage: NfcReadStage.authenticating,
              rootCause: 'BacNotImplemented',
            ),
          );
      }
      trace.emit(NfcTraceStep.readEfCom);
      return await passport.readEfCOM();
    } on NfcFailure {
      rethrow;
    } on PassportError catch (e) {
      throw NfcErrorClassifier.fromPassportError(
        e,
        stage: NfcReadStage.authenticating,
      );
    } on Exception catch (e) {
      throw NfcErrorClassifier.fromGenericException(
        e,
        stage: NfcReadStage.authenticating,
      );
    }
  }

  Future<NfcReadResult> _readDeclaredDataGroups(
    Passport passport,
    EfCOM efCom,
    _TraceSession trace,
  ) async {
    final warnings = <NfcWarning>[];
    final identity = await _readIdentity(passport, efCom, warnings, trace);
    final faceImageBytes =
        await _readFaceImage(passport, efCom, warnings, trace);
    final extendedData = await _readExtendedData(passport, efCom, warnings, trace);
    final aa = await _readAaEvidence(passport, efCom, warnings, trace);

    return NfcReadResult(
      sessionId: trace.sessionId,
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
    List<NfcWarning> warnings,
    _TraceSession trace,
  ) async {
    trace.emit(NfcTraceStep.readDg1);
    if (!efCom.dgTags.contains(EfDG1.TAG)) {
      warnings.add(const NfcWarning(NfcWarningType.dg1NotDeclared));
      return _emptyIdentity();
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
        warnings.add(const NfcWarning(NfcWarningType.idNumberMissing));
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
        throw NfcErrorClassifier.tagLost(stage: NfcReadStage.reading);
      }
      warnings.add(const NfcWarning(NfcWarningType.dg1ReadFailed));
      return _emptyIdentity();
    }
  }

  Future<Uint8List?> _readFaceImage(
    Passport passport,
    EfCOM efCom,
    List<NfcWarning> warnings,
    _TraceSession trace,
  ) async {
    trace.emit(NfcTraceStep.readDg2);
    if (!efCom.dgTags.contains(EfDG2.TAG)) {
      warnings.add(const NfcWarning(NfcWarningType.dg2NotDeclared));
      return null;
    }
    try {
      // dmrtd tự parse cấu trúc TLV/biometric-data-block của DG2 — KHÔNG tự
      // cắt base64 thủ công.
      final imageData = (await passport.readEfDG2()).imageData;
      if (imageData == null) {
        warnings.add(const NfcWarning(NfcWarningType.dg2NoImage));
      }
      return imageData;
    } catch (e) {
      if (NfcErrorClassifier.isTagLostError(e)) {
        throw NfcErrorClassifier.tagLost(stage: NfcReadStage.reading);
      }
      warnings.add(const NfcWarning(NfcWarningType.dg2ReadFailed));
      return null;
    }
  }

  Future<Map<String, String>?> _readExtendedData(
    Passport passport,
    EfCOM efCom,
    List<NfcWarning> warnings,
    _TraceSession trace,
  ) async {
    trace.emit(NfcTraceStep.readDg13);
    if (!efCom.dgTags.contains(EfDG13.TAG)) return null;
    try {
      final rawBytes = (await passport.readEfDG13()).toBytes();
      final extendedData = NfcDg13Parser.parse(rawBytes);
      if (extendedData.isEmpty) {
        warnings.add(const NfcWarning(NfcWarningType.dg13Empty));
      }
      return extendedData;
    } catch (e) {
      if (NfcErrorClassifier.isTagLostError(e)) {
        throw NfcErrorClassifier.tagLost(stage: NfcReadStage.reading);
      }
      // Không nội suy nội dung exception vào warning — DG13 chứa PII mở rộng,
      // message exception thô có thể vô tình lộ dữ liệu.
      warnings.add(const NfcWarning(NfcWarningType.dg13ReadOrParseFailed));
      return null;
    }
  }

  Future<_AaEvidence> _readAaEvidence(
    Passport passport,
    EfCOM efCom,
    List<NfcWarning> warnings,
    _TraceSession trace,
  ) async {
    trace.emit(NfcTraceStep.readDg15Aa);
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
      // Chỉ log fingerprint + độ dài (metadata), KHÔNG log giá trị thật.
      trace.emit(
        NfcTraceStep.readDg15Aa,
        bytes: signature.lengthInBytes,
        detail:
            'challenge=${_fingerprint(challenge)} sig=${_fingerprint(signature)}',
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
        throw NfcErrorClassifier.tagLost(stage: NfcReadStage.reading);
      }
      warnings.add(const NfcWarning(NfcWarningType.aaFailed));
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

  _Identity _emptyIdentity() => (
        idNumber: null,
        fullName: null,
        dateOfBirth: null,
        dateOfExpiry: null,
        gender: null,
        nationality: null,
      );
}

/// Trạng thái 1 phiên đọc dùng để phát breadcrumb [NfcTraceEvent].
class _TraceSession {
  _TraceSession(this.sessionId, this.onTrace) : startedAt = DateTime.now();

  final String sessionId;
  final void Function(NfcTraceEvent event) onTrace;
  final DateTime startedAt;

  void emit(
    NfcTraceStep step, {
    int? sw1,
    int? sw2,
    int? bytes,
    String? detail,
  }) {
    final now = DateTime.now();
    onTrace(
      NfcTraceEvent(
        sessionId: sessionId,
        step: step,
        timestamp: now,
        elapsed: now.difference(startedAt),
        sw1: sw1,
        sw2: sw2,
        dataLengthBytes: bytes,
        detail: detail,
      ),
    );
  }
}

void _noop(NfcTraceEvent _) {}

/// Giới hạn độ dài chi tiết để an toàn khi log. Nội dung ở đây là text
/// giao thức/technical (luồng xác thực), không phải nội dung dữ liệu thẻ.
String? _sanitize(String? value) {
  if (value == null) return null;
  final s = value.trim();
  if (s.isEmpty) return null;
  const max = 200;
  return s.length > max ? '${s.substring(0, max)}…' : s;
}
