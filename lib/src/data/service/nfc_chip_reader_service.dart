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

/// Kết quả đọc DG15 và xác thực chủ động (Active Authentication).
typedef _AaResult = ({
  Uint8List? dg15Bytes,
  Uint8List? challenge,
  Uint8List? signature,
  Uint8List? publicKeyBytes,
  String? algorithm,
  AaEvidenceStatus status,
});

/// Đọc 1 phiên chip MRTD: connect → PACE/BAC → EF.COM → DG1/DG2/DG13/DG14/DG15+AA/SOD,
/// tất cả trong cùng 1 lần chạm thẻ duy nhất.
///
/// Mỗi phiên sinh 1 `sessionId` và phát các [NfcTraceEvent] breadcrumb cho từng
/// bước qua `read(onTrace: ...)` — chỉ chứa metadata an toàn (bước, SW1/SW2,
/// độ dài byte, thời lượng ms, chi tiết đã sanitize), KHÔNG kèm PII (MRZ/tên/ảnh/key).
/// App hứng stream này để log, Sentry hoặc phân tích bottleneck thời gian.
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

  /// Đọc trọn vẹn dữ liệu thô (raw bytes và chuỗi Base64) phục vụ gửi Backend xác thực.
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

  /// Huỷ phiên đang chạy — ngắt kết nối khiến `read()` tự thoát qua nhánh lỗi.
  Future<void> cancel() => _nfcProvider.disconnect();

  /// Điều phối vòng đời 1 phiên NFC (kết nối, timeout, chuyển đổi stage, cleanup).
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
      final detailMsg = details?.rootCause != null && details?.detail != null
          ? '${details!.rootCause}: ${details.detail}'
          : details?.rootCause ?? details?.detail;

      trace.emit(
        NfcTraceStep.failed,
        sw1: details?.sw1,
        sw2: details?.sw2,
        detail: detailMsg,
      );
      throw failure;
    } finally {
      await _nfcProvider.disconnect();
    }
  }

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
      final efCom = await passport.readEfCOM();
      trace.emit(NfcTraceStep.readEfCom, bytes: efCom.toBytes().lengthInBytes);
      return efCom;
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

  /// Đọc tuần tự tất cả Data Group trong 1 phiên chạm thẻ duy nhất.
  /// Trả về đồng thời cả [NfcParsedResult] và [NfcRawResult] đã được liên kết chéo.
  Future<({NfcParsedResult parsed, NfcRawResult raw})> _readCardSessionData(
    Passport passport,
    EfCOM efCom,
    _TraceSession trace,
    NfcReadInput input,
  ) async {
    final warnings = <NfcWarning>[];
    final comBytes = efCom.toBytes();

    // 1. DG1 (MRZ + Identity + Kiểm tra CCCD input)
    final dg1Result = await _readDg1(
      passport: passport,
      efCom: efCom,
      input: input,
      trace: trace,
      warnings: warnings,
    );

    // 2. DG2 (Ảnh chân dung sinh trắc học)
    final dg2Result = await _readDg2(
      passport: passport,
      efCom: efCom,
      trace: trace,
      warnings: warnings,
    );

    // 3. DG13 (Dữ liệu mở rộng CCCD Việt Nam)
    final dg13Result = await _readDg13(
      passport: passport,
      efCom: efCom,
      trace: trace,
      warnings: warnings,
    );

    // 4. DG14 (Security Infos)
    final dg14Bytes = await _readDg14(
      passport: passport,
      efCom: efCom,
      trace: trace,
      warnings: warnings,
    );

    // 5. DG15 + Active Authentication (Bằng chứng chống sao chép chip)
    final aaResult = await _readDg15Aa(
      passport: passport,
      efCom: efCom,
      trace: trace,
      warnings: warnings,
    );

    // 6. EF.SOD (Document Security Object - Chữ ký Bộ Công An C06)
    final sodBytes = await _readEfSod(
      passport: passport,
      trace: trace,
      warnings: warnings,
    );

    // 7. Tạo và liên kết 2 đối tượng kết quả
    return _buildSessionResults(
      sessionId: trace.sessionId,
      identity: dg1Result.identity,
      dg1Bytes: dg1Result.bytes,
      dg2Bytes: dg2Result.bytes,
      faceImageBytes: dg2Result.faceImageBytes,
      dg13Bytes: dg13Result.bytes,
      dg13Data: dg13Result.data,
      dg14Bytes: dg14Bytes,
      aaResult: aaResult,
      sodBytes: sodBytes,
      comBytes: comBytes,
      warnings: warnings,
    );
  }

  // ===========================================================================
  // Các phương thức đọc chuyên biệt từng Data Group (Modular Readers)
  // ===========================================================================

  Future<({Uint8List? bytes, _Identity identity})> _readDg1({
    required Passport passport,
    required EfCOM efCom,
    required NfcReadInput input,
    required _TraceSession trace,
    required List<NfcWarning> warnings,
  }) async {
    if (!efCom.dgTags.contains(EfDG1.TAG)) {
      warnings.add(const NfcWarning(NfcWarningType.dg1NotDeclared));
      return (bytes: null, identity: _emptyIdentity());
    }

    final stopwatch = Stopwatch()..start();
    trace.emit(NfcTraceStep.readDg1);

    try {
      final dg1 = await passport.readEfDG1();
      final dg1Bytes = dg1.toBytes();
      stopwatch.stop();

      trace.emit(
        NfcTraceStep.readDg1,
        bytes: dg1Bytes.lengthInBytes,
        detail: '${stopwatch.elapsedMilliseconds}ms',
      );

      final mrz = dg1.mrz;
      final fullName = '${mrz.lastName} ${mrz.firstName}'.trim();
      final optionalData = mrz.optionalData;
      final idNumber =
          optionalData.length >= 12 ? optionalData.substring(0, 12) : null;

      if (idNumber == null) {
        warnings.add(const NfcWarning(NfcWarningType.idNumberMissing));
      }

      final identity = (
        idNumber: idNumber,
        fullName: fullName.isEmpty ? null : fullName,
        dateOfBirth: mrz.dateOfBirth,
        dateOfExpiry: mrz.dateOfExpiry,
        gender: _parseGender(mrz.gender),
        nationality: mrz.nationality,
      );

      // Đối chiếu số CCCD nhập vào với số định danh thực tế trên DG1
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

      return (bytes: dg1Bytes, identity: identity);
    } catch (e) {
      if (e is NfcFailure) rethrow;
      _handleDgReadError(
        step: NfcTraceStep.readDg1,
        warningType: NfcWarningType.dg1ReadFailed,
        error: e,
        trace: trace,
        warnings: warnings,
      );
      return (bytes: null, identity: _emptyIdentity());
    }
  }

  Future<({Uint8List? bytes, Uint8List? faceImageBytes})> _readDg2({
    required Passport passport,
    required EfCOM efCom,
    required _TraceSession trace,
    required List<NfcWarning> warnings,
  }) async {
    if (!efCom.dgTags.contains(EfDG2.TAG)) {
      warnings.add(const NfcWarning(NfcWarningType.dg2NotDeclared));
      return (bytes: null, faceImageBytes: null);
    }

    final stopwatch = Stopwatch()..start();
    trace.emit(NfcTraceStep.readDg2);

    try {
      final dg2 = await passport.readEfDG2();
      final dg2Bytes = dg2.toBytes();
      final faceImageBytes = dg2.imageData;
      stopwatch.stop();

      trace.emit(
        NfcTraceStep.readDg2,
        bytes: dg2Bytes.lengthInBytes,
        detail: '${stopwatch.elapsedMilliseconds}ms',
      );

      if (faceImageBytes == null) {
        warnings.add(const NfcWarning(NfcWarningType.dg2NoImage));
      }

      return (bytes: dg2Bytes, faceImageBytes: faceImageBytes);
    } catch (e) {
      _handleDgReadError(
        step: NfcTraceStep.readDg2,
        warningType: NfcWarningType.dg2ReadFailed,
        error: e,
        trace: trace,
        warnings: warnings,
      );
      return (bytes: null, faceImageBytes: null);
    }
  }

  Future<({Uint8List? bytes, _Dg13Data data})> _readDg13({
    required Passport passport,
    required EfCOM efCom,
    required _TraceSession trace,
    required List<NfcWarning> warnings,
  }) async {
    if (!efCom.dgTags.contains(EfDG13.TAG)) {
      return (bytes: null, data: (data: null, fullName: null));
    }

    final stopwatch = Stopwatch()..start();
    trace.emit(NfcTraceStep.readDg13);

    try {
      final dg13Bytes = (await passport.readEfDG13()).toBytes();
      stopwatch.stop();

      trace.emit(
        NfcTraceStep.readDg13,
        bytes: dg13Bytes.lengthInBytes,
        detail: '${stopwatch.elapsedMilliseconds}ms',
      );

      final parsed = NfcDg13Parser.parseAll(dg13Bytes);
      if (parsed.data.isEmpty && parsed.fullName == null) {
        warnings.add(const NfcWarning(NfcWarningType.dg13Empty));
      }

      return (
        bytes: dg13Bytes,
        data: (data: parsed.data, fullName: parsed.fullName),
      );
    } catch (e) {
      _handleDgReadError(
        step: NfcTraceStep.readDg13,
        warningType: NfcWarningType.dg13ReadOrParseFailed,
        error: e,
        trace: trace,
        warnings: warnings,
      );
      return (bytes: null, data: (data: null, fullName: null));
    }
  }

  Future<Uint8List?> _readDg14({
    required Passport passport,
    required EfCOM efCom,
    required _TraceSession trace,
    required List<NfcWarning> warnings,
  }) async {
    if (!efCom.dgTags.contains(EfDG14.TAG)) {
      return null;
    }

    final stopwatch = Stopwatch()..start();
    trace.emit(NfcTraceStep.readDg14);

    try {
      final dg14 = await passport.readEfDG14();
      final dg14Bytes = dg14.toBytes();
      stopwatch.stop();

      trace.emit(
        NfcTraceStep.readDg14,
        bytes: dg14Bytes.lengthInBytes,
        detail: '${stopwatch.elapsedMilliseconds}ms',
      );

      return dg14Bytes;
    } catch (e) {
      _handleDgReadError(
        step: NfcTraceStep.readDg14,
        warningType: NfcWarningType.dg14ReadFailed,
        error: e,
        trace: trace,
        warnings: warnings,
      );
      return null;
    }
  }

  Future<_AaResult> _readDg15Aa({
    required Passport passport,
    required EfCOM efCom,
    required _TraceSession trace,
    required List<NfcWarning> warnings,
  }) async {
    if (!efCom.dgTags.contains(EfDG15.TAG)) {
      return (
        dg15Bytes: null,
        challenge: null,
        signature: null,
        publicKeyBytes: null,
        algorithm: null,
        status: AaEvidenceStatus.notSupported,
      );
    }

    final stopwatch = Stopwatch()..start();
    trace.emit(NfcTraceStep.readDg15Aa);

    try {
      final dg15 = await passport.readEfDG15();
      final dg15Bytes = dg15.toBytes();
      final challenge = _generateAaChallenge();
      final signature = await passport.activeAuthenticate(challenge);
      stopwatch.stop();

      final publicKeyBytes = dg15.aaPublicKey.rawSubjectPublicKey();
      final algorithm = _describeAaAlgorithm(dg15.aaPublicKey.type);

      trace.emit(
        NfcTraceStep.readDg15Aa,
        bytes: signature.lengthInBytes,
        detail:
            '${stopwatch.elapsedMilliseconds}ms, challenge=${_fingerprint(challenge)} sig=${_fingerprint(signature)}',
      );

      return (
        dg15Bytes: dg15Bytes,
        challenge: challenge,
        signature: signature,
        publicKeyBytes: publicKeyBytes,
        algorithm: algorithm,
        status: AaEvidenceStatus.captured,
      );
    } catch (e) {
      _handleDgReadError(
        step: NfcTraceStep.readDg15Aa,
        warningType: NfcWarningType.aaFailed,
        error: e,
        trace: trace,
        warnings: warnings,
      );
      return (
        dg15Bytes: null,
        challenge: null,
        signature: null,
        publicKeyBytes: null,
        algorithm: null,
        status: AaEvidenceStatus.failed,
      );
    }
  }

  Future<Uint8List?> _readEfSod({
    required Passport passport,
    required _TraceSession trace,
    required List<NfcWarning> warnings,
  }) async {
    final stopwatch = Stopwatch()..start();
    trace.emit(NfcTraceStep.readEfSod);

    try {
      final sod = await passport.readEfSOD();
      final sodBytes = sod.toBytes();
      stopwatch.stop();

      trace.emit(
        NfcTraceStep.readEfSod,
        bytes: sodBytes.lengthInBytes,
        detail: '${stopwatch.elapsedMilliseconds}ms',
      );

      return sodBytes;
    } catch (e) {
      _handleDgReadError(
        step: NfcTraceStep.readEfSod,
        warningType: NfcWarningType.sodReadFailed,
        error: e,
        trace: trace,
        warnings: warnings,
      );
      return null;
    }
  }

  /// Xử lý tập trung mọi ngoại lệ khi đọc Data Group:
  /// - Rethrow ngay lập tức nếu là [NfcFailure] hoặc [tagLost] để huỷ phiên đọc
  /// - Với các lỗi không-fatal khác: bóc tách status word SW1/SW2, format chi tiết kỹ thuật
  ///   đã sanitize, ghi vào warnings và phát trace event chẩn đoán.
  void _handleDgReadError({
    required NfcTraceStep step,
    required NfcWarningType warningType,
    required Object error,
    required _TraceSession trace,
    required List<NfcWarning> warnings,
  }) {
    if (error is NfcFailure) throw error;
    if (NfcErrorClassifier.isTagLostError(error)) {
      throw NfcErrorClassifier.tagLost(stage: NfcReadStage.reading);
    }

    final sw = _extractStatusWords(error);
    final detail = _formatErrorDetail(error, sw1: sw.sw1, sw2: sw.sw2);

    warnings.add(NfcWarning(warningType, detail: detail));
    trace.emit(
      step,
      sw1: sw.sw1,
      sw2: sw.sw2,
      detail: 'failed: $detail',
    );
  }

  /// Ghép nối kết quả [NfcRawResult] và [NfcParsedResult] với liên kết chéo 2 chiều.
  ({NfcParsedResult parsed, NfcRawResult raw}) _buildSessionResults({
    required String sessionId,
    required _Identity identity,
    required Uint8List? dg1Bytes,
    required Uint8List? dg2Bytes,
    required Uint8List? faceImageBytes,
    required Uint8List? dg13Bytes,
    required _Dg13Data dg13Data,
    required Uint8List? dg14Bytes,
    required _AaResult aaResult,
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

  // ===========================================================================
  // Helpers
  // ===========================================================================

  Uint8List _generateAaChallenge() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(Passport.aaChallengeLen, (_) => random.nextInt(256)),
    );
  }

  /// Bóc tách status words (SW1, SW2) từ exception nếu có.
  ({int? sw1, int? sw2}) _extractStatusWords(Object error) {
    if (error is PassportError) {
      return (sw1: error.code?.sw1, sw2: error.code?.sw2);
    }
    try {
      final dynamic dyn = error;
      final dynamic sw = dyn.code ?? dyn.sw;
      if (sw != null) {
        final sw1 = sw.sw1;
        final sw2 = sw.sw2;
        if (sw1 is int && sw2 is int) {
          return (sw1: sw1, sw2: sw2);
        }
      }
    } catch (_) {}
    return (sw1: null, sw2: null);
  }

  /// Định dạng chi tiết lỗi kỹ thuật kèm mã SW (nếu có) và sanitize an toàn.
  String _formatErrorDetail(Object error, {int? sw1, int? sw2}) {
    final buffer = StringBuffer();
    if (sw1 != null && sw2 != null) {
      final hex1 = sw1.toRadixString(16).padLeft(2, '0').toUpperCase();
      final hex2 = sw2.toRadixString(16).padLeft(2, '0').toUpperCase();
      buffer.write('SW=$hex1$hex2 ');
    }
    if (error is PassportError) {
      buffer.write(error.message);
    } else {
      buffer.write(error.toString());
    }
    return _sanitize(buffer.toString()) ?? 'unknown error';
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
