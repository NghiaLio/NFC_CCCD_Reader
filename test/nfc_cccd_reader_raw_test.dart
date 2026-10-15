import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_cccd_reader/nfc_cccd_reader.dart';
import 'package:nfc_cccd_reader/src/nfc_cccd_reader_base.dart';

class _MockNfcRepository implements NfcRepository {
  NfcRawResult? mockRawResult;
  NfcParsedResult? mockParsedResult;

  @override
  Future<NfcAvailabilityStatus> checkAvailability() async =>
      NfcAvailabilityStatus.available;

  @override
  Future<NfcParsedResult> readChip(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  }) async {
    onStage?.call(NfcReadStage.reading);
    return mockParsedResult ??
        const NfcParsedResult(sessionId: 'test-mock-read');
  }

  @override
  Future<NfcParsedResult> readParsedChip(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  }) =>
      readChip(input, onStage: onStage, onTrace: onTrace);

  @override
  Future<NfcRawResult> readRawChip(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  }) async {
    onStage?.call(NfcReadStage.reading);
    return mockRawResult ??
        const NfcRawResult(
          sessionId: 'test-mock-raw',
          dg1: 'ZGd4',
          sod: 'c29k',
        );
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  group('NfcCccdReader readRaw', () {
    test('calls repository.readRawChip and propagates stages', () async {
      final repo = _MockNfcRepository();
      final reader = NfcCccdReaderBase.withRepository(repo);

      final stages = <NfcReadStage>[];
      final input = NfcReadInput.pace(can: '123456');

      final result = await reader.readRaw(
        input,
        onStage: (s) => stages.add(s),
      );

      expect(result.sessionId, 'test-mock-raw');
      expect(result.dg1, 'ZGd4');
      expect(result.sod, 'c29k');
      expect(stages, contains(NfcReadStage.reading));

      reader.dispose();
    });

    test('calls repository.readParsedChip for readParsed', () async {
      final repo = _MockNfcRepository();
      repo.mockParsedResult = const NfcParsedResult(
        sessionId: 'test-parsed-session',
        idNumber: '001099012345',
        fullName: 'NGUYEN VAN ANH',
      );
      final reader = NfcCccdReaderBase.withRepository(repo);

      final input = NfcReadInput.pace(can: '123456');
      final result = await reader.readParsed(input);

      expect(result.sessionId, 'test-parsed-session');
      expect(result.idNumber, '001099012345');
      expect(result.fullName, 'NGUYEN VAN ANH');

      reader.dispose();
    });
  });
}

