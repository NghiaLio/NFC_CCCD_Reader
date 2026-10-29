import 'dart:typed_data';

import 'package:dmrtd/dmrtd.dart';

import '../../../domain/entities/nfc_warning.dart';
import '../../../domain/enums/nfc_trace_step.dart';
import '../../../domain/enums/nfc_warning_type.dart';
import '../lifecycle/nfc_trace_session.dart';
import 'dg_reader_helper.dart';

/// Đọc và xử lý Data Group 14: thông tin cấu hình bảo mật thẻ (Security Infos).
class Dg14Reader {
  const Dg14Reader();

  Future<Uint8List?> read({
    required Passport passport,
    required EfCOM efCom,
    required NfcTraceSession trace,
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
      DgReaderHelper.handleDgReadError(
        step: NfcTraceStep.readDg14,
        warningType: NfcWarningType.dg14ReadFailed,
        error: e,
        trace: trace,
        warnings: warnings,
      );
      return null;
    }
  }
}
