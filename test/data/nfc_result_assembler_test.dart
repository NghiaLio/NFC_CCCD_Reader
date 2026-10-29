import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_cccd_reader/nfc_cccd_reader.dart';
import 'package:nfc_cccd_reader/src/data/service/result/nfc_result_assembler.dart';

void main() {
  group('NfcResultAssembler', () {
    test('assembles and mutually links NfcParsedResult and NfcRawResult', () {
      final dg1Bytes = Uint8List.fromList([1, 2, 3]);
      final dg2Bytes = Uint8List.fromList([4, 5, 6]);
      final faceBytes = Uint8List.fromList([7, 8, 9]);
      final comBytes = Uint8List.fromList([10, 11]);

      final results = NfcResultAssembler.assemble(
        sessionId: 'session-xyz',
        identity: (
          idNumber: '001099123456',
          fullName: 'NGUYEN VAN A',
          dateOfBirth: DateTime(1999, 1, 1),
          dateOfExpiry: DateTime(2039, 1, 1),
          gender: NfcGender.male,
          nationality: 'VNM',
        ),
        dg1Bytes: dg1Bytes,
        dg2Bytes: dg2Bytes,
        faceImageBytes: faceBytes,
        dg13Bytes: null,
        dg13Data: (data: {'placeOfOrigin': 'Ha Noi'}, fullName: 'NGUYỄN VĂN A'),
        dg14Bytes: null,
        aaResult: (
          dg15Bytes: null,
          challenge: null,
          signature: null,
          publicKeyBytes: null,
          algorithm: null,
          status: AaEvidenceStatus.notSupported,
        ),
        sodBytes: null,
        comBytes: comBytes,
        warnings: const [NfcWarning(NfcWarningType.dg13Empty)],
      );

      final parsed = results.parsed;
      final raw = results.raw;

      // Kiểm tra liên kết chéo 2 chiều
      expect(raw.parsed, same(parsed));
      expect(parsed.raw?.sessionId, raw.sessionId);
      expect(parsed.raw?.dg1, raw.dg1);

      // Kiểm tra dữ liệu Parsed
      expect(parsed.sessionId, 'session-xyz');
      expect(parsed.idNumber, '001099123456');
      expect(parsed.fullName, 'NGUYEN VAN A');
      expect(parsed.fullNameWithDiacritics, 'NGUYỄN VĂN A');
      expect(parsed.extendedData, {'placeOfOrigin': 'Ha Noi'});
      expect(parsed.faceImageBytes, faceBytes);
      expect(parsed.warnings.length, 1);

      // Kiểm tra dữ liệu Raw
      expect(raw.sessionId, 'session-xyz');
      expect(raw.dg1, base64Encode(dg1Bytes));
      expect(raw.dg2, base64Encode(dg2Bytes));
      expect(raw.com, base64Encode(comBytes));
      expect(raw.sod, isNull);
    });

    test('fullNameWithDiacritics falls back to fullName when DG13 has no name', () {
      final results = NfcResultAssembler.assemble(
        sessionId: 'session-fallback',
        identity: (
          idNumber: '001099123456',
          fullName: 'TRAN THI B',
          dateOfBirth: null,
          dateOfExpiry: null,
          gender: NfcGender.female,
          nationality: 'VNM',
        ),
        dg1Bytes: null,
        dg2Bytes: null,
        faceImageBytes: null,
        dg13Bytes: null,
        dg13Data: (data: null, fullName: null),
        dg14Bytes: null,
        aaResult: (
          dg15Bytes: null,
          challenge: null,
          signature: null,
          publicKeyBytes: null,
          algorithm: null,
          status: AaEvidenceStatus.notSupported,
        ),
        sodBytes: null,
        comBytes: Uint8List(0),
        warnings: const [],
      );

      expect(results.parsed.fullName, 'TRAN THI B');
      expect(results.parsed.fullNameWithDiacritics, 'TRAN THI B');
    });
  });
}
