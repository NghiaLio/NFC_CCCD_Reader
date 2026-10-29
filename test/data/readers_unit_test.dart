import 'dart:typed_data';

// ignore: implementation_imports
import 'package:dmrtd/src/proto/iso7816/response_apdu.dart' show StatusWord;
import 'package:dmrtd/dmrtd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_cccd_reader/nfc_cccd_reader.dart';
import 'package:nfc_cccd_reader/src/data/service/lifecycle/nfc_trace_session.dart';
import 'package:nfc_cccd_reader/src/data/service/readers/dg15_aa_reader.dart';
import 'package:nfc_cccd_reader/src/data/service/readers/dg1_reader.dart';
import 'package:nfc_cccd_reader/src/data/service/readers/dg_reader_helper.dart';

void main() {
  group('Dg1Reader helpers', () {
    test('parseGender maps ICAO string correctly', () {
      expect(Dg1Reader.parseGender('M'), NfcGender.male);
      expect(Dg1Reader.parseGender('F'), NfcGender.female);
      expect(Dg1Reader.parseGender('<'), NfcGender.unspecified);
      expect(Dg1Reader.parseGender('X'), NfcGender.unspecified);
    });

    test('emptyIdentity returns all nulls', () {
      final identity = Dg1Reader.emptyIdentity();
      expect(identity.idNumber, isNull);
      expect(identity.fullName, isNull);
      expect(identity.dateOfBirth, isNull);
      expect(identity.dateOfExpiry, isNull);
      expect(identity.gender, isNull);
      expect(identity.nationality, isNull);
    });
  });

  group('Dg15AaReader helpers', () {
    test('generateAaChallenge produces 8 random bytes', () {
      final challenge1 = Dg15AaReader.generateAaChallenge();
      final challenge2 = Dg15AaReader.generateAaChallenge();

      expect(challenge1.length, 8);
      expect(challenge2.length, 8);
      // Nonces shouldn't be identical
      expect(challenge1, isNot(equals(challenge2)));
    });

    test('fingerprint produces 12 character hex substring', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final fp = Dg15AaReader.fingerprint(bytes);
      expect(fp.length, 12);
      expect(RegExp(r'^[0-9a-f]{12}$').hasMatch(fp), isTrue);
    });

    test('describeAaAlgorithm maps key type to RSA/EC', () {
      expect(Dg15AaReader.describeAaAlgorithm(AAPublicKeyType.RSA), 'RSA');
      expect(Dg15AaReader.describeAaAlgorithm(AAPublicKeyType.ECC), 'EC');
    });
  });

  group('DgReaderHelper', () {
    test('extractStatusWords extracts sw1 and sw2 from PassportError or dynamic object', () {
      const swCode = StatusWord(sw1: 0x6A, sw2: 0x82);
      final error = PassportError('File not found', code: swCode);
      final sw = DgReaderHelper.extractStatusWords(error);
      expect(sw.sw1, 0x6A);
      expect(sw.sw2, 0x82);

      final format = DgReaderHelper.formatErrorDetail(error, sw1: sw.sw1, sw2: sw.sw2);
      expect(format, contains('SW=6A82'));
      expect(format, contains('File not found'));
    });

    test('handleDgReadError rethrows tagLost and NfcFailure', () {
      final session = NfcTraceSession('test-err', (_) {});
      final warnings = <NfcWarning>[];

      expect(
        () => DgReaderHelper.handleDgReadError(
          step: NfcTraceStep.readDg1,
          warningType: NfcWarningType.dg1ReadFailed,
          error: const NfcFailure(NfcFailureType.tagLost),
          trace: session,
          warnings: warnings,
        ),
        throwsA(isA<NfcFailure>()),
      );

      expect(
        () => DgReaderHelper.handleDgReadError(
          step: NfcTraceStep.readDg1,
          warningType: NfcWarningType.dg1ReadFailed,
          error: Exception('ComProviderError: connection dropped'),
          trace: session,
          warnings: warnings,
        ),
        throwsA(isA<NfcFailure>().having((e) => e.type, 'type', NfcFailureType.tagLost)),
      );
    });

    test('handleDgReadError records non-fatal errors as warnings', () {
      final traces = <NfcTraceEvent>[];
      final session = NfcTraceSession('test-non-fatal', traces.add);
      final warnings = <NfcWarning>[];

      DgReaderHelper.handleDgReadError(
        step: NfcTraceStep.readDg2,
        warningType: NfcWarningType.dg2ReadFailed,
        error: Exception('Corrupted image stream'),
        trace: session,
        warnings: warnings,
      );

      expect(warnings.length, 1);
      expect(warnings[0].type, NfcWarningType.dg2ReadFailed);
      expect(warnings[0].detail, contains('Corrupted image stream'));

      expect(traces.length, 1);
      expect(traces[0].step, NfcTraceStep.readDg2);
      expect(traces[0].detail, contains('Corrupted image stream'));
    });
  });
}
