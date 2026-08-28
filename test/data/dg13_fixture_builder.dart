import 'dart:typed_data';
import 'package:asn1lib/asn1lib.dart';

/// Dựng DG13 giả đúng cấu trúc thật nhưng toàn bộ giá trị là dữ liệu bịa,
/// dùng cho unit test — KHÔNG BAO GIỜ dùng hex từ CCCD thật trong test.
Uint8List buildFakeDg13({
  required Map<int, String> flatFields, // field 1-12, 15, 16
  List<String>? parents, // field 13: [cha, mẹ]
  String? spouse, // field 14
}) {
  final set = ASN1Set();

  void addFlat(int number, String value) {
    final seq = ASN1Sequence()
      ..add(ASN1Integer(BigInt.from(number)))
      ..add(ASN1UTF8String(value));
    set.add(seq);
  }

  flatFields.forEach(addFlat);

  if (parents != null) {
    final nested = ASN1Sequence();
    for (final p in parents) {
      nested.add(ASN1UTF8String(p));
    }
    set.add(
      ASN1Sequence()
        ..add(ASN1Integer(BigInt.from(13)))
        ..add(nested),
    );
  }

  if (spouse != null) {
    final nested = ASN1Sequence()..add(ASN1UTF8String(spouse));
    set.add(
      ASN1Sequence()
        ..add(ASN1Integer(BigInt.from(14)))
        ..add(nested),
    );
  }

  final content = ASN1Sequence()
    ..add(ASN1Integer(BigInt.one))
    ..add(ASN1ObjectIdentifier.fromComponentString('1.0.10646.1.0.8'))
    ..add(set);

  final outer = ASN1Sequence()..add(content);
  return outer.encodedBytes;
}
