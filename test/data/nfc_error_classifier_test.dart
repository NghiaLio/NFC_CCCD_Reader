import 'package:flutter_test/flutter_test.dart';
import 'package:dmrtd/dmrtd.dart';
// dmrtd không export StatusWord qua barrel công khai — chỉ dùng trong test để
// dựng fixture PassportError, KHÔNG dùng trong code chính (xem
// NfcErrorClassifier._isAuthFailedStatus, tránh naming type không public).
// ignore: implementation_imports
import 'package:dmrtd/src/proto/iso7816/response_apdu.dart' show StatusWord;
import 'package:nfc_cccd_reader/src/data/service/nfc_error_classifier.dart';
import 'package:nfc_cccd_reader/src/domain/enums/nfc_failure_type.dart';

void main() {
  group('NfcErrorClassifier', () {
    test('status word 63/00 -> wrongCan', () {
      final error = PassportError(
        'auth failed',
        code: const StatusWord(sw1: 0x63, sw2: 0x00),
      );
      final failure = NfcErrorClassifier.fromPassportError(error);
      expect(failure.type, NfcFailureType.wrongCan);
    });

    test('message chứa "ComProviderError" (đã bị PACE bọc lại) -> tagLost', () {
      final failure = NfcErrorClassifier.fromGenericException(
        Exception(
          'PACEError: PACE(3); Failed: ComProviderError: transceive failed',
        ),
      );
      expect(failure.type, NfcFailureType.tagLost);
    });

    test('lỗi PACE khác không liên quan mất kết nối -> wrongCan', () {
      final failure = NfcErrorClassifier.fromGenericException(
        Exception(
            'PACEError: Auth token from ICC and terminal are not the same'),
      );
      expect(failure.type, NfcFailureType.wrongCan);
    });
  });
}
