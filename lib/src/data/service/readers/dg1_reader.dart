import 'dart:typed_data';

import 'package:dmrtd/dmrtd.dart';

import '../../../domain/entities/nfc_error_details.dart';
import '../../../domain/entities/nfc_failure.dart';
import '../../../domain/entities/nfc_read_input.dart';
import '../../../domain/entities/nfc_warning.dart';
import '../../../domain/enums/nfc_failure_type.dart';
import '../../../domain/enums/nfc_gender.dart';
import '../../../domain/enums/nfc_read_stage.dart';
import '../../../domain/enums/nfc_trace_step.dart';
import '../../../domain/enums/nfc_warning_type.dart';
import '../lifecycle/nfc_trace_session.dart';
import '../result/nfc_result_assembler.dart';
import 'dg_reader_helper.dart';

/// Đọc và xử lý Data Group 1 (MRZ): trích xuất thông tin nhân thân (họ tên,
/// số định danh, ngày sinh, ngày hết hạn, giới tính, quốc tịch) và đối chiếu số CCCD.
class Dg1Reader {
  const Dg1Reader();

  Future<({Uint8List? bytes, CardIdentity identity})> read({
    required Passport passport,
    required EfCOM efCom,
    required NfcReadInput input,
    required NfcTraceSession trace,
    required List<NfcWarning> warnings,
  }) async {
    if (!efCom.dgTags.contains(EfDG1.TAG)) {
      warnings.add(const NfcWarning(NfcWarningType.dg1NotDeclared));
      return (bytes: null, identity: emptyIdentity());
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
        gender: parseGender(mrz.gender),
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
      DgReaderHelper.handleDgReadError(
        step: NfcTraceStep.readDg1,
        warningType: NfcWarningType.dg1ReadFailed,
        error: e,
        trace: trace,
        warnings: warnings,
      );
      return (bytes: null, identity: emptyIdentity());
    }
  }

  /// MRZ mã hoá giới tính bằng 1 ký tự ICAO: 'M', 'F', hoặc '<' (không khai báo).
  static NfcGender parseGender(String mrzGender) => switch (mrzGender) {
        'M' => NfcGender.male,
        'F' => NfcGender.female,
        _ => NfcGender.unspecified,
      };

  static CardIdentity emptyIdentity() => (
        idNumber: null,
        fullName: null,
        dateOfBirth: null,
        dateOfExpiry: null,
        gender: null,
        nationality: null,
      );
}
