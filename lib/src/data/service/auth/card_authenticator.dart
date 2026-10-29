import 'package:dmrtd/dmrtd.dart';
import 'package:dmrtd/extensions.dart';

import '../../../core/nfc_constants.dart';
import '../../../domain/entities/nfc_error_details.dart';
import '../../../domain/entities/nfc_failure.dart';
import '../../../domain/entities/nfc_read_input.dart';
import '../../../domain/enums/nfc_failure_type.dart';
import '../../../domain/enums/nfc_read_stage.dart';
import '../../../domain/enums/nfc_session_mode.dart';
import '../../../domain/enums/nfc_trace_step.dart';
import '../can_key_adapter.dart';
import '../lifecycle/nfc_trace_session.dart';
import '../nfc_error_classifier.dart';

/// Interface cho các cơ chế xác thực thẻ MRTD (PACE, BAC...).
abstract interface class CardAuthenticator {
  Future<void> authenticate(Passport passport, NfcReadInput input);
}

/// Xác thực PACE (Password Authenticated Connection Establishment) qua mã CAN (CCCD VN).
class PaceAuthenticator implements CardAuthenticator {
  const PaceAuthenticator();

  @override
  Future<void> authenticate(Passport passport, NfcReadInput input) async {
    final efCardAccess = EfCardAccess.fromBytes(
      NfcConstants.keyAccessDataNFCIos.parseHex(),
    );
    final accessKey = buildCanAccessKey(input.can!);
    await passport.startSessionPACE(accessKey, efCardAccess);
  }
}

/// Xác thực BAC (Basic Access Control) cho giấy tờ quốc tế.
/// Hiện tại là stub ném [NfcFailureType.bacFailed].
class BacAuthenticator implements CardAuthenticator {
  const BacAuthenticator();

  @override
  Future<void> authenticate(Passport passport, NfcReadInput input) async {
    throw const NfcFailure(
      NfcFailureType.bacFailed,
      errorDetails: NfcErrorDetails(
        stage: NfcReadStage.authenticating,
        rootCause: 'BacNotImplemented',
      ),
    );
  }
}

/// Điều phối quá trình xác thực phiên và đọc EF.COM từ chip thẻ.
class CardSessionAuthenticator {
  CardSessionAuthenticator({
    CardAuthenticator? paceAuthenticator,
    CardAuthenticator? bacAuthenticator,
  })  : _paceAuthenticator = paceAuthenticator ?? const PaceAuthenticator(),
        _bacAuthenticator = bacAuthenticator ?? const BacAuthenticator();

  final CardAuthenticator _paceAuthenticator;
  final CardAuthenticator _bacAuthenticator;

  Future<EfCOM> authenticateAndReadEfCom(
    Passport passport,
    NfcReadInput input,
    NfcTraceSession trace,
  ) async {
    trace.emit(NfcTraceStep.sessionStart);
    try {
      switch (input.mode) {
        case NfcSessionMode.pace:
          await _paceAuthenticator.authenticate(passport, input);
        case NfcSessionMode.bac:
          await _bacAuthenticator.authenticate(passport, input);
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
}
