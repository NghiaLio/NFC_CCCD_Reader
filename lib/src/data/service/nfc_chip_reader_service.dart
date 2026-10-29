import 'dart:async';

import 'package:dmrtd/dmrtd.dart';

import '../../domain/entities/nfc_ios_alert_state.dart';
import '../../domain/entities/nfc_parsed_result.dart';
import '../../domain/entities/nfc_raw_result.dart';
import '../../domain/entities/nfc_read_input.dart';
import '../../domain/entities/nfc_trace_event.dart';
import '../../domain/entities/nfc_warning.dart';
import '../../domain/enums/nfc_read_stage.dart';
import 'ios/nfc_ios_alert_manager.dart';
import 'lifecycle/nfc_session_lifecycle.dart';
import 'lifecycle/nfc_trace_session.dart';
import 'readers/dg13_reader.dart';
import 'readers/dg14_reader.dart';
import 'readers/dg15_aa_reader.dart';
import 'readers/dg1_reader.dart';
import 'readers/dg2_reader.dart';
import 'readers/ef_sod_reader.dart';
import 'result/nfc_result_assembler.dart';

/// Đọc 1 phiên chip MRTD: connect → PACE/BAC → EF.COM → DG1/DG2/DG13/DG14/DG15+AA/SOD,
/// tất cả trong cùng 1 lần chạm thẻ duy nhất.
///
/// Lớp đóng vai trò Orchestrator (bộ điều phối): kết hợp vòng đời phiên [NfcSessionLifecycle],
/// hiển thị giao diện iOS [NfcIosAlertManager], các reader chuyên biệt cho từng Data Group,
/// và lắp ghép kết quả [NfcResultAssembler].
class NfcChipReaderService {
  factory NfcChipReaderService({
    NfcProvider? nfcProvider,
    Duration connectTimeout = const Duration(seconds: 20),
    NfcIosAlertBuilder? iosAlertBuilder,
    Dg1Reader? dg1Reader,
    Dg2Reader? dg2Reader,
    Dg13Reader? dg13Reader,
    Dg14Reader? dg14Reader,
    Dg15AaReader? dg15AaReader,
    EfSodReader? efSodReader,
    NfcSessionLifecycle? lifecycle,
  }) {
    final provider = nfcProvider ?? NfcProvider();
    final effectiveLifecycle = lifecycle ??
        NfcSessionLifecycle(
          nfcProvider: provider,
          iosAlertManager: NfcIosAlertManager(
            nfcProvider: provider,
            iosAlertBuilder: iosAlertBuilder,
          ),
          connectTimeout: connectTimeout,
        );
    return NfcChipReaderService._(
      nfcProvider: provider,
      connectTimeout: connectTimeout,
      lifecycle: effectiveLifecycle,
      dg1Reader: dg1Reader ?? const Dg1Reader(),
      dg2Reader: dg2Reader ?? const Dg2Reader(),
      dg13Reader: dg13Reader ?? const Dg13Reader(),
      dg14Reader: dg14Reader ?? const Dg14Reader(),
      dg15AaReader: dg15AaReader ?? const Dg15AaReader(),
      efSodReader: efSodReader ?? const EfSodReader(),
    );
  }

  const NfcChipReaderService._({
    required NfcProvider nfcProvider,
    required this.connectTimeout,
    required NfcSessionLifecycle lifecycle,
    required Dg1Reader dg1Reader,
    required Dg2Reader dg2Reader,
    required Dg13Reader dg13Reader,
    required Dg14Reader dg14Reader,
    required Dg15AaReader dg15AaReader,
    required EfSodReader efSodReader,
  })  : _nfcProvider = nfcProvider,
        _lifecycle = lifecycle,
        _dg1Reader = dg1Reader,
        _dg2Reader = dg2Reader,
        _dg13Reader = dg13Reader,
        _dg14Reader = dg14Reader,
        _dg15AaReader = dg15AaReader,
        _efSodReader = efSodReader;

  final NfcProvider _nfcProvider;
  final Duration connectTimeout;
  final NfcSessionLifecycle _lifecycle;
  final Dg1Reader _dg1Reader;
  final Dg2Reader _dg2Reader;
  final Dg13Reader _dg13Reader;
  final Dg14Reader _dg14Reader;
  final Dg15AaReader _dg15AaReader;
  final EfSodReader _efSodReader;

  /// Đọc 1 phiên chip MRTD và phân tích cú pháp sang [NfcParsedResult].
  Future<NfcParsedResult> read(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  }) =>
      _lifecycle.run(
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
      _lifecycle.run(
        input: input,
        onStage: onStage,
        onTrace: onTrace,
        reader: (passport, efCom, trace) async =>
            (await _readCardSessionData(passport, efCom, trace, input)).raw,
      );

  /// Huỷ phiên đang chạy — ngắt kết nối khiến `read()` tự thoát qua nhánh lỗi.
  Future<void> cancel() => _nfcProvider.disconnect();

  /// Đọc tuần tự tất cả Data Group trong 1 phiên chạm thẻ duy nhất.
  /// Trả về đồng thời cả [NfcParsedResult] và [NfcRawResult] đã được liên kết chéo.
  Future<({NfcParsedResult parsed, NfcRawResult raw})> _readCardSessionData(
    Passport passport,
    EfCOM efCom,
    NfcTraceSession trace,
    NfcReadInput input,
  ) async {
    final warnings = <NfcWarning>[];
    final comBytes = efCom.toBytes();

    // 1. DG1 (MRZ + Identity + Kiểm tra CCCD input)
    final dg1Result = await _dg1Reader.read(
      passport: passport,
      efCom: efCom,
      input: input,
      trace: trace,
      warnings: warnings,
    );

    // 2. DG2 (Ảnh chân dung sinh trắc học)
    final dg2Result = await _dg2Reader.read(
      passport: passport,
      efCom: efCom,
      trace: trace,
      warnings: warnings,
    );

    // 3. DG13 (Dữ liệu mở rộng CCCD Việt Nam)
    final dg13Result = await _dg13Reader.read(
      passport: passport,
      efCom: efCom,
      trace: trace,
      warnings: warnings,
    );

    // 4. DG14 (Security Infos)
    final dg14Bytes = await _dg14Reader.read(
      passport: passport,
      efCom: efCom,
      trace: trace,
      warnings: warnings,
    );

    // 5. DG15 + Active Authentication (Bằng chứng chống sao chép chip)
    final aaResult = await _dg15AaReader.read(
      passport: passport,
      efCom: efCom,
      trace: trace,
      warnings: warnings,
    );

    // 6. EF.SOD (Document Security Object - Chữ ký Bộ Công An C06)
    final sodBytes = await _efSodReader.read(
      passport: passport,
      trace: trace,
      warnings: warnings,
    );

    // 7. Tạo và liên kết 2 đối tượng kết quả
    return NfcResultAssembler.assemble(
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
}
