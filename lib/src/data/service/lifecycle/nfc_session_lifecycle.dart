import 'dart:async';

import 'package:dmrtd/dmrtd.dart';

import '../../../core/nfc_session_id.dart';
import '../../../domain/entities/nfc_error_details.dart';
import '../../../domain/entities/nfc_failure.dart';
import '../../../domain/entities/nfc_read_input.dart';
import '../../../domain/entities/nfc_trace_event.dart';
import '../../../domain/enums/nfc_failure_type.dart';
import '../../../domain/enums/nfc_read_stage.dart';
import '../../../domain/enums/nfc_trace_step.dart';
import '../auth/card_authenticator.dart';
import '../ios/nfc_ios_alert_manager.dart';
import '../nfc_error_classifier.dart';
import 'nfc_trace_session.dart';

/// Quản lý vòng đời 1 phiên quét thẻ NFC: kết nối phần cứng, kiểm tra timeout,
/// kiểm tra ISO-7816, xác thực phiên thẻ, chuyển đổi giai đoạn và dọn dẹp tài nguyên.
class NfcSessionLifecycle {
  NfcSessionLifecycle({
    required NfcProvider nfcProvider,
    required NfcIosAlertManager iosAlertManager,
    CardSessionAuthenticator? authenticator,
    this.connectTimeout = const Duration(seconds: 20),
  })  : _nfcProvider = nfcProvider,
        _iosAlertManager = iosAlertManager,
        _authenticator = authenticator ?? CardSessionAuthenticator();

  final NfcProvider _nfcProvider;
  final NfcIosAlertManager _iosAlertManager;
  final CardSessionAuthenticator _authenticator;
  final Duration connectTimeout;

  Future<T> run<T>({
    required NfcReadInput input,
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
    required Future<T> Function(
      Passport passport,
      EfCOM efCom,
      NfcTraceSession trace,
    ) reader,
  }) async {
    _iosAlertManager.reset();
    final trace = NfcTraceSession(
      generateNfcSessionId(),
      onTrace,
      onStep: _iosAlertManager.updateAlert,
    );

    var stage = NfcReadStage.waitingForCard;
    try {
      trace.emit(NfcTraceStep.started);
      onStage?.call(stage);

      trace.emit(NfcTraceStep.connecting);
      try {
        final connectMsg = _iosAlertManager.getConnectMessage();
        await _nfcProvider.connect(
          timeout: connectTimeout,
          iosAlertMessage: connectMsg,
        );
      } on NfcProviderError catch (e) {
        throw NfcFailure(
          NfcFailureType.timeout,
          errorDetails: NfcErrorDetails(
            stage: stage,
            rootCause: 'NfcProviderError',
            detail: NfcTraceSession.sanitize(e.toString()),
          ),
        );
      }

      // connect() của flutter_nfc_kit tự disconnect và return lặng lẽ nếu tag
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
      final efCom = await _authenticator.authenticateAndReadEfCom(
        passport,
        input,
        trace,
      );
      trace.emit(NfcTraceStep.sessionEstablished);

      stage = NfcReadStage.reading;
      onStage?.call(stage);
      final result = await reader(passport, efCom, trace);

      stage = NfcReadStage.validating;
      onStage?.call(stage);
      trace.emit(NfcTraceStep.completed);
      await _iosAlertManager.finishSession();
      return result;
    } catch (e) {
      var failure = e is NfcFailure ? e : _classify(e, stage);
      // Bảo đảm mọi NfcFailure ra ngoài đều mang sessionId (để nhóm log)
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
      await _iosAlertManager.finishSession(failure: failure);
      throw failure;
    } finally {
      // Lưới an toàn: isConnected() đã false thì là no-op.
      await _nfcProvider.disconnect();
    }
  }

  NfcFailure _classify(Object e, NfcReadStage stage) {
    final base = NfcErrorClassifier.isTagLostError(e)
        ? NfcErrorClassifier.tagLost(stage: stage)
        : NfcErrorClassifier.fromGenericException(e, stage: stage);
    return NfcFailure(base.type, errorDetails: base.errorDetails);
  }
}
