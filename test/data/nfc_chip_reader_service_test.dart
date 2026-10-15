import 'package:dmrtd/dmrtd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_cccd_reader/nfc_cccd_reader.dart';
import 'package:nfc_cccd_reader/src/data/service/nfc_chip_reader_service.dart';

class _FakeNfcProvider extends NfcProvider {
  bool isConnectedResult = false;
  bool throwNfcProviderError = false;
  bool disconnectCalled = false;

  @override
  Future<void> connect({
    Duration? timeout,
    String iosAlertMessage = '',
  }) async {
    if (throwNfcProviderError) {
      throw NfcProviderError('Polling tag timed out');
    }
  }

  @override
  bool isConnected() => isConnectedResult;

  @override
  Future<void> disconnect({
    String? iosAlertMessage,
    String? iosErrorMessage,
  }) async {
    disconnectCalled = true;
    isConnectedResult = false;
  }
}

void main() {
  group('NfcChipReaderService Session Lifecycle', () {
    test('throws timeout when NfcProvider fails to connect', () async {
      final fakeProvider = _FakeNfcProvider()..throwNfcProviderError = true;
      final service = NfcChipReaderService(nfcProvider: fakeProvider);

      final traces = <NfcTraceEvent>[];
      final input = NfcReadInput.pace(can: '123456');

      try {
        await service.read(input, onTrace: traces.add);
        fail('Should have thrown NfcFailure');
      } on NfcFailure catch (e) {
        expect(e.type, NfcFailureType.timeout);
        expect(e.sessionId, isNotNull);
        expect(e.errorDetails?.rootCause, 'NfcProviderError');
        expect(e.errorDetails?.stage, NfcReadStage.waitingForCard);
      }

      expect(traces.map((t) => t.step), contains(NfcTraceStep.started));
      expect(traces.map((t) => t.step), contains(NfcTraceStep.connecting));
      expect(traces.map((t) => t.step), contains(NfcTraceStep.failed));
      expect(fakeProvider.disconnectCalled, isTrue);
    });

    test('throws timeout when tag is not ISO-7816 (isConnected is false)', () async {
      final fakeProvider = _FakeNfcProvider()..isConnectedResult = false;
      final service = NfcChipReaderService(nfcProvider: fakeProvider);

      final input = NfcReadInput.pace(can: '123456');

      try {
        await service.read(input);
        fail('Should have thrown NfcFailure');
      } on NfcFailure catch (e) {
        expect(e.type, NfcFailureType.timeout);
        expect(e.sessionId, isNotNull);
        expect(e.errorDetails?.rootCause, 'NonIso7816Tag');
      }

      expect(fakeProvider.disconnectCalled, isTrue);
    });

    test('cancel calls disconnect on provider', () async {
      final fakeProvider = _FakeNfcProvider();
      final service = NfcChipReaderService(nfcProvider: fakeProvider);

      await service.cancel();
      expect(fakeProvider.disconnectCalled, isTrue);
    });
  });
}

