import 'dart:typed_data';

import 'package:dmrtd/dmrtd.dart';

import '../../../domain/entities/nfc_warning.dart';
import '../../../domain/enums/nfc_trace_step.dart';
import '../../../domain/enums/nfc_warning_type.dart';
import '../../parser/nfc_dg13_parser.dart';
import '../lifecycle/nfc_trace_session.dart';
import '../result/nfc_result_assembler.dart';
import 'dg_reader_helper.dart';

/// Đọc và xử lý Data Group 13: dữ liệu mở rộng đặc thù của CCCD Việt Nam (quê quán,
/// nơi thường trú, dân tộc, tôn giáo, tên có dấu, thông tin cha/mẹ/vợ/chồng...).
class Dg13Reader {
  const Dg13Reader();

  Future<({Uint8List? bytes, Dg13Data data})> read({
    required Passport passport,
    required EfCOM efCom,
    required NfcTraceSession trace,
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
      DgReaderHelper.handleDgReadError(
        step: NfcTraceStep.readDg13,
        warningType: NfcWarningType.dg13ReadOrParseFailed,
        error: e,
        trace: trace,
        warnings: warnings,
      );
      return (bytes: null, data: (data: null, fullName: null));
    }
  }
}
