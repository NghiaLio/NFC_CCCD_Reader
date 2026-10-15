import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dmrtd/dmrtd.dart';
import 'package:dmrtd/extensions.dart';

import '../../core/nfc_constants.dart';
import '../../core/nfc_session_id.dart';
import '../../domain/entities/nfc_error_details.dart';
import '../../domain/entities/nfc_failure.dart';
import '../../domain/entities/nfc_parsed_result.dart';
import '../../domain/entities/nfc_raw_result.dart';
import '../../domain/entities/nfc_read_input.dart';
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

/// Kết quả đọc DG13: [data] = extendedData (key tiếng Anh), [fullName] =
/// field 2 (tên, có thể kèm dấu) tách riêng. Cả hai `null` nếu không đọc được.
typedef _Dg13Data = ({Map<String, String>? data, String? fullName});

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

  Future<NfcParsedResult> read(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  }) =>
      _runSession(
        input: input,
        onStage: onStage,
        onTrace: onTrace,
        reader: (passport, efCom, trace) async =>
            (await _readCardSessionData(passport, efCom, trace, input)).parsed,
      );

  /// Tên gọi tường minh cho [read]: đọc và phân tích cú pháp dữ liệu chip.
  Future<NfcParsedResult> readParsed(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  }) =>
      read(input, onStage: onStage, onTrace: onTrace);

  Future<NfcRawResult> readRaw(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  }) =>
      _runSession(
        input: input,
        onStage: onStage,
        onTrace: onTrace,
        reader: (passport, efCom, trace) async =>
            (await _readCardSessionData(passport, efCom, trace, input)).raw,
      );

  Future<T> _runSession<T>({
    required NfcReadInput input,
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
    required Future<T> Function(
      Passport passport,
      EfCOM efCom,
      _TraceSession trace,
    ) reader,
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
      final result = await reader(passport, efCom, trace);

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

  Future<({NfcParsedResult parsed, NfcRawResult raw})> _readCardSessionData(
    Passport passport,
    EfCOM efCom,
    _TraceSession trace,
    NfcReadInput input,
  ) async {
    final warnings = <NfcWarning>[];
    final comBytes = efCom.toBytes();

    // 1. DG1 (MRZ + Identity)
    Uint8List? dg1Bytes;
    var identity = _emptyIdentity();
    if (!efCom.dgTags.contains(EfDG1.TAG)) {
      warnings.add(const NfcWarning(NfcWarningType.dg1NotDeclared));
    } else {
      trace.emit(NfcTraceStep.readDg1);
      try {
        final dg1 = await passport.readEfDG1();
        dg1Bytes = dg1.toBytes();
        trace.emit(NfcTraceStep.readDg1, bytes: dg1Bytes.lengthInBytes);

        final mrz = dg1.mrz;
        final fullName = '${mrz.lastName} ${mrz.firstName}'.trim();
        final optionalData = mrz.optionalData;
        final idNumber = optionalData.length >= 12
            ? optionalData.substring(0, 12)
            : null;
        if (idNumber == null) {
          warnings.add(const NfcWarning(NfcWarningType.idNumberMissing));
        }

        identity = (
          idNumber: idNumber,
          fullName: fullName.isEmpty ? null : fullName,
          dateOfBirth: mrz.dateOfBirth,
          dateOfExpiry: mrz.dateOfExpiry,
          gender: _parseGender(mrz.gender),
          nationality: mrz.nationality,
        );

        if (input.cccdNumber != null && idNumber != null) {
          if (input.cccdNumber != idNumber) {
            throw const NfcFailure(
              NfcFailureType.wrongCan,
              errorDetails: NfcErrorDetails(
                stage: NfcReadStage.validating,
                rootCause: 'CccdNumberMismatch',
                detail: 'Input CCCD number does not match idNumber from DG1',
              ),
            );
          }
        }
      } catch (e) {
        if (e is NfcFailure) rethrow;
        if (NfcErrorClassifier.isTagLostError(e)) {
          throw NfcErrorClassifier.tagLost(stage: NfcReadStage.reading);
        }
        warnings.add(const NfcWarning(NfcWarningType.dg1ReadFailed));
      }
    }

    // 2. DG2 (Ảnh khuôn mặt)
    Uint8List? dg2Bytes;
    Uint8List? faceImageBytes;
    if (!efCom.dgTags.contains(EfDG2.TAG)) {
      warnings.add(const NfcWarning(NfcWarningType.dg2NotDeclared));
    } else {
      trace.emit(NfcTraceStep.readDg2);
      try {
        final dg2 = await passport.readEfDG2();
        dg2Bytes = dg2.toBytes();
        faceImageBytes = dg2.imageData;
        trace.emit(NfcTraceStep.readDg2, bytes: dg2Bytes.lengthInBytes);
        if (faceImageBytes == null) {
          warnings.add(const NfcWarning(NfcWarningType.dg2NoImage));
        }
      } catch (e) {
        if (NfcErrorClassifier.isTagLostError(e)) {
          throw NfcErrorClassifier.tagLost(stage: NfcReadStage.reading);
        }
        warnings.add(const NfcWarning(NfcWarningType.dg2ReadFailed));
      }
    }

    // 3. DG13 (Dữ liệu mở rộng CCCD VN)
    Uint8List? dg13Bytes;
    _Dg13Data dg13Data = (data: null, fullName: null);
    if (efCom.dgTags.contains(EfDG13.TAG)) {
      trace.emit(NfcTraceStep.readDg13);
      try {
        dg13Bytes = (await passport.readEfDG13()).toBytes();
        trace.emit(NfcTraceStep.readDg13, bytes: dg13Bytes.lengthInBytes);
        final parsed = NfcDg13Parser.parseAll(dg13Bytes);
        dg13Data = (data: parsed.data, fullName: parsed.fullName);
        if (parsed.data.isEmpty && parsed.fullName == null) {
          warnings.add(const NfcWarning(NfcWarningType.dg13Empty));
        }
      } catch (e) {
        if (NfcErrorClassifier.isTagLostError(e)) {
          throw NfcErrorClassifier.tagLost(stage: NfcReadStage.reading);
        }
        warnings.add(const NfcWarning(NfcWarningType.dg13ReadOrParseFailed));
      }
    }

    // 4. DG14 (Security Infos)
    Uint8List? dg14Bytes;
    if (efCom.dgTags.contains(EfDG14.TAG)) {
      trace.emit(NfcTraceStep.readDg14);
      try {
        final dg14 = await passport.readEfDG14();
        dg14Bytes = dg14.toBytes();
        trace.emit(NfcTraceStep.readDg14, bytes: dg14Bytes.lengthInBytes);
      } catch (e) {
        if (NfcErrorClassifier.isTagLostError(e)) {
          throw NfcErrorClassifier.tagLost(stage: NfcReadStage.reading);
        }
        warnings.add(const NfcWarning(NfcWarningType.dg14ReadFailed));
      }
    }

    // 5. DG15 + Active Authentication
    Uint8List? dg15Bytes;
    Uint8List? aaChallenge;
    Uint8List? aaSignature;
    Uint8List? aaPublicKeyBytes;
    String? aaAlgorithm;
    var aaStatus = AaEvidenceStatus.notSupported;
    if (efCom.dgTags.contains(EfDG15.TAG)) {
      trace.emit(NfcTraceStep.readDg15Aa);
      try {
        final dg15 = await passport.readEfDG15();
        dg15Bytes = dg15.toBytes();
        final challenge = _generateAaChallenge();
        final signature = await passport.activeAuthenticate(challenge);
        aaChallenge = challenge;
        aaSignature = signature;
        aaPublicKeyBytes = dg15.aaPublicKey.rawSubjectPublicKey();
        aaAlgorithm = _describeAaAlgorithm(dg15.aaPublicKey.type);
        aaStatus = AaEvidenceStatus.captured;
        trace.emit(
          NfcTraceStep.readDg15Aa,
          bytes: signature.lengthInBytes,
          detail:
              'challenge=${_fingerprint(challenge)} sig=${_fingerprint(signature)}',
        );
      } catch (e) {
        if (NfcErrorClassifier.isTagLostError(e)) {
          throw NfcErrorClassifier.tagLost(stage: NfcReadStage.reading);
        }
        warnings.add(const NfcWarning(NfcWarningType.aaFailed));
        aaStatus = AaEvidenceStatus.failed;
      }
    }

    // 6. EF.SOD (Document Security Object)
    Uint8List? sodBytes;
    trace.emit(NfcTraceStep.readEfSod);
    try {
      final sod = await passport.readEfSOD();
      sodBytes = sod.toBytes();
      trace.emit(NfcTraceStep.readEfSod, bytes: sodBytes.lengthInBytes);
    } catch (e) {
      if (NfcErrorClassifier.isTagLostError(e)) {
        throw NfcErrorClassifier.tagLost(stage: NfcReadStage.reading);
      }
      warnings.add(const NfcWarning(NfcWarningType.sodReadFailed));
    }

    final baseRawResult = NfcRawResult.fromBytes(
      sessionId: trace.sessionId,
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
    );

    final parsedResult = NfcParsedResult(
      sessionId: trace.sessionId,
      idNumber: identity.idNumber,
      fullName: identity.fullName,
      fullNameWithDiacritics: dg13Data.fullName ?? identity.fullName,
      dateOfBirth: identity.dateOfBirth,
      dateOfExpiry: identity.dateOfExpiry,
      gender: identity.gender,
      nationality: identity.nationality,
      faceImageBytes: faceImageBytes,
      extendedData: dg13Data.data,
      aaChallenge: aaChallenge,
      aaSignature: aaSignature,
      aaPublicKeyBytes: aaPublicKeyBytes,
      aaAlgorithm: aaAlgorithm,
      aaStatus: aaStatus,
      isChipAuthenticityVerified: false,
      warnings: warnings,
      raw: baseRawResult,
    );

    final rawResult = baseRawResult.copyWith(parsed: parsedResult);

    return (parsed: parsedResult, raw: rawResult);
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
