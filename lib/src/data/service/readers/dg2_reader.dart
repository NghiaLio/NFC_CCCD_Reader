import 'dart:typed_data';

import 'package:dmrtd/dmrtd.dart';

import '../../../domain/entities/nfc_warning.dart';
import '../../../domain/enums/nfc_trace_step.dart';
import '../../../domain/enums/nfc_warning_type.dart';
import '../lifecycle/nfc_trace_session.dart';
import 'dg_reader_helper.dart';

/// Đọc và xử lý Data Group 2: ảnh chân dung sinh trắc học khuôn mặt.
class Dg2Reader {
  const Dg2Reader();

  Future<({Uint8List? bytes, Uint8List? faceImageBytes})> read({
    required Passport passport,
    required EfCOM efCom,
    required NfcTraceSession trace,
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
      DgReaderHelper.handleDgReadError(
        step: NfcTraceStep.readDg2,
        warningType: NfcWarningType.dg2ReadFailed,
        error: e,
        trace: trace,
        warnings: warnings,
      );
      return (bytes: null, faceImageBytes: null);
    }
  }
}
