import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_cccd_reader/nfc_cccd_reader.dart';

void main() {
  group('NfcReadInput', () {
    test('paceFromCccdNumber tự cắt đúng 6 số cuối làm CAN', () {
      final input = NfcReadInput.paceFromCccdNumber('999999123456');
      expect(input.can, '123456');
      expect(input.mode, NfcSessionMode.pace);
    });

    test('CCCD sai định dạng ném ArgumentError', () {
      expect(() => NfcReadInput.paceFromCccdNumber('abc'), throwsArgumentError);
    });

    test('CAN không đủ 6 số ném ArgumentError', () {
      expect(() => NfcReadInput.pace(can: '123'), throwsArgumentError);
    });

    test('bac() với documentNumber rỗng ném ArgumentError', () {
      expect(
        () => NfcReadInput.bac(
          documentNumber: '  ',
          dateOfBirth: DateTime(1990, 1, 1),
          dateOfExpiry: DateTime(2030, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('toString() không lộ giá trị CAN thật', () {
      final input = NfcReadInput.pace(can: '123456');
      expect(input.toString(), isNot(contains('123456')));
    });
  });
}
