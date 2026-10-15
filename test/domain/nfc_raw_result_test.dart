import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_cccd_reader/nfc_cccd_reader.dart';

void main() {
  group('NfcRawResult', () {
    test('fromBytes encodes fields to base64 correctly', () {
      final dg1Bytes = Uint8List.fromList([1, 2, 3, 4]);
      final sodBytes = Uint8List.fromList([5, 6, 7, 8]);
      final dg13Bytes = Uint8List.fromList([9, 10, 11]);
      final dg2Bytes = Uint8List.fromList([12, 13]);
      final dg14Bytes = Uint8List.fromList([14, 15]);
      final dg15Bytes = Uint8List.fromList([16, 17]);
      final comBytes = Uint8List.fromList([18, 19]);
      final challenge = Uint8List.fromList([20, 21]);
      final signature = Uint8List.fromList([22, 23]);

      final result = NfcRawResult.fromBytes(
        sessionId: 'test-session',
        dg1Bytes: dg1Bytes,
        sodBytes: sodBytes,
        dg13Bytes: dg13Bytes,
        dg2Bytes: dg2Bytes,
        dg14Bytes: dg14Bytes,
        dg15Bytes: dg15Bytes,
        comBytes: comBytes,
        aaChallenge: challenge,
        aaSignature: signature,
        aaStatus: AaEvidenceStatus.captured,
      );

      expect(result.sessionId, 'test-session');
      expect(result.dg1, base64Encode(dg1Bytes));
      expect(result.sod, base64Encode(sodBytes));
      expect(result.dg13, base64Encode(dg13Bytes));
      expect(result.dg2, base64Encode(dg2Bytes));
      expect(result.dg14, base64Encode(dg14Bytes));
      expect(result.dg15, base64Encode(dg15Bytes));
      expect(result.com, base64Encode(comBytes));
      expect(result.aaChallengeBase64, base64Encode(challenge));
      expect(result.aaSignatureBase64, base64Encode(signature));
      expect(result.aaStatus, AaEvidenceStatus.captured);

      // toMap
      final map = result.toMap();
      expect(map.keys, containsAll(['dg1', 'sod', 'dg13', 'dg2', 'dg14', 'dg15', 'com']));
      expect(map['dg1'], base64Encode(dg1Bytes));
      expect(map['sod'], base64Encode(sodBytes));

      // toJson
      final json = result.toJson();
      expect(json['dg1'], base64Encode(dg1Bytes));
      expect(json['com'], base64Encode(comBytes));

      // toHexMap
      final hexMap = result.toHexMap();
      expect(hexMap['dg1'], '01020304');
      expect(hexMap['sod'], '05060708');
    });

    test('handles null fields gracefully', () {
      final result = NfcRawResult.fromBytes(
        sessionId: 'empty-session',
      );

      expect(result.dg1, isNull);
      expect(result.sod, isNull);
      expect(result.dg13, isNull);
      expect(result.dg2, isNull);
      expect(result.dg14, isNull);
      expect(result.dg15, isNull);
      expect(result.com, isNull);

      final map = result.toMap();
      expect(map['dg1'], isNull);
      expect(map['sod'], isNull);

      final json = result.toJson();
      expect(json.isEmpty, isTrue);

      final hexMap = result.toHexMap();
      expect(hexMap['dg1'], isNull);
    });
  });
}

