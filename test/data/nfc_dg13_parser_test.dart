import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_cccd_reader/src/data/parser/nfc_dg13_parser.dart';
import 'dart:typed_data';
import 'dg13_fixture_builder.dart';

void main() {
  group('NfcDg13Parser', () {
    test('parse các field đơn không trùng lặp với top-level (6, 7, 11)', () {
      final bytes = buildFakeDg13(
        flatFields: {
          6: 'KINH', // ethnicity giả
          7: 'KHONG', // religion giả
          11: '01012020', // issueDate giả
        },
      );
      final result = NfcDg13Parser.parse(bytes);
      expect(result['ethnicity'], 'KINH');
      expect(result['religion'], 'KHONG');
      expect(result['issueDate'], '01012020');
    });

    test(
      'bỏ qua field trùng với NfcReadResult top-level (1,2,3,4,5,12) dù thẻ có công bố',
      () {
        final bytes = buildFakeDg13(
          flatFields: {
            1: '999999999999', // idNumber giả — trùng top-level
            2: 'NGUYEN VAN A', // fullName giả — trùng top-level
            3: '01011990', // dateOfBirth giả — trùng top-level
            4: 'NAM', // gender giả — trùng top-level
            5: 'VNM', // nationality giả — trùng top-level
            12: '01012030', // dateOfExpiry giả — trùng top-level
            6: 'KINH', // field không trùng — vẫn phải parse bình thường
          },
        );
        final result = NfcDg13Parser.parse(bytes);
        expect(result.containsKey('idNumber'), isFalse);
        expect(result.containsKey('fullName'), isFalse);
        expect(result.containsKey('dateOfBirth'), isFalse);
        expect(result.containsKey('gender'), isFalse);
        expect(result.containsKey('nationality'), isFalse);
        expect(result.containsKey('dateOfExpiry'), isFalse);
        expect(result['ethnicity'], 'KINH');
      },
    );

    test('field 13 (cha/mẹ) parse đúng dạng ghép', () {
      final bytes = buildFakeDg13(
        flatFields: {},
        parents: ['NGUYEN VAN B', 'TRAN THI C'],
      );
      final result = NfcDg13Parser.parse(bytes);
      expect(result['fatherName'], 'NGUYEN VAN B');
      expect(result['motherName'], 'TRAN THI C');
    });

    test('field 14 (vợ/chồng) vắng mặt khi độc thân — không xuất hiện', () {
      final bytes = buildFakeDg13(flatFields: {6: 'KINH'});
      final result = NfcDg13Parser.parse(bytes);
      expect(result.containsKey('spouseName'), isFalse);
    });

    test('bytes hỏng ném Dg13ParseError', () {
      expect(
        () => NfcDg13Parser.parse(Uint8List.fromList([0xFF, 0x00])),
        throwsA(isA<Dg13ParseError>()),
      );
    });
  });
}
