import 'package:dmrtd/dmrtd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_cccd_reader/nfc_cccd_reader.dart';
import 'package:nfc_cccd_reader/src/data/service/ios/nfc_ios_alert_manager.dart';

class _FakeNfcProviderForAlert extends NfcProvider {
  String? lastAlertMessage;
  String? lastErrorMessage;
  bool disconnectCalled = false;

  @override
  Future<void> setIosAlertMessage(String message) async {
    lastAlertMessage = message;
  }

  @override
  Future<void> disconnect({
    String? iosAlertMessage,
    String? iosErrorMessage,
  }) async {
    disconnectCalled = true;
    lastAlertMessage = iosAlertMessage;
    lastErrorMessage = iosErrorMessage;
  }
}

void main() {
  group('NfcIosAlertManager', () {
    test('getConnectMessage returns default when no builder is provided', () {
      final fakeProvider = _FakeNfcProviderForAlert();
      final manager = NfcIosAlertManager(nfcProvider: fakeProvider);

      expect(
        manager.getConnectMessage(),
        NfcIosAlertManager.defaultIosConnectMessage,
      );
    });

    test('progressByStep contains all expected steps', () {
      expect(NfcIosAlertManager.progressByStep[NfcTraceStep.connecting], 0.0);
      expect(NfcIosAlertManager.progressByStep[NfcTraceStep.readDg2], 0.55);
      expect(NfcIosAlertManager.progressByStep[NfcTraceStep.completed], 1.0);
    });

    test('reset clears last message cache', () {
      final fakeProvider = _FakeNfcProviderForAlert();
      final manager = NfcIosAlertManager(nfcProvider: fakeProvider);
      manager.reset();
      expect(manager.getConnectMessage(), NfcIosAlertManager.defaultIosConnectMessage);
    });
  });
}
