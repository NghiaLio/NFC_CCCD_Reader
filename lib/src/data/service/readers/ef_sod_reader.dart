import 'dart:typed_data';

import 'package:dmrtd/dmrtd.dart';

import '../../../domain/entities/nfc_warning.dart';
import '../../../domain/enums/nfc_trace_step.dart';
import '../../../domain/enums/nfc_warning_type.dart';
import '../lifecycle/nfc_trace_session.dart';
import 'dg_reader_helper.dart';

/// Đọc và xử lý EF.SOD (Document Security Object): chứa chữ ký số của cơ quan phát
/// hành thẻ (C06 - Bộ Công An) và băm SHA của toàn bộ các Data Group.
class EfSodReader {
  const EfSodReader();

  Future<Uint8List?> read({
    required Passport passport,
    required NfcTraceSession trace,
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
      DgReaderHelper.handleDgReadError(
        step: NfcTraceStep.readEfSod,
        warningType: NfcWarningType.sodReadFailed,
        error: e,
        trace: trace,
        warnings: warnings,
      );
      return null;
    }
  }
}
