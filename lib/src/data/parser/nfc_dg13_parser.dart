import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:collection/collection.dart';

/// Parser ASN.1 cho DG13 — dữ liệu mở rộng của CCCD Việt Nam (không có trong
/// chuẩn ICAO 9303 gốc, dmrtd không có accessor sẵn cho DG này).
///
/// Cấu trúc byte thật đã giải mã trực tiếp từ hex mẫu thật (không suy đoán):
/// ```
/// APPLICATION 13 (0x6D, EfDG13.TAG)
///   SEQUENCE
///     INTEGER (version = 1)
///     OID (1.0.10646.1.0.8 — chưa xác nhận chính thức ý nghĩa)
///     SET  — N field, mỗi field: SEQUENCE { INTEGER fieldNumber, [value] }
/// ```
/// Field được đánh số 1..16 rõ ràng qua INTEGER đứng đầu mỗi SEQUENCE con —
/// KHÔNG dựa vào thứ tự vị trí phẳng (field có thể vắng mặt hoàn toàn, không
/// phải chuỗi rỗng — ví dụ field 15 "giấy tờ khác" nếu công dân không có).
///
/// **Chủ ý bỏ qua** các field trùng với dữ liệu top-level của
/// `NfcReadResult` (đã có nguồn đáng tin cậy hơn từ DG1/MRZ): field 1
/// (idNumber), 2 (fullName), 3 (dateOfBirth), 4 (gender), 5 (nationality),
/// 12 (dateOfExpiry). Giữ 2 nguồn dữ liệu trùng nhau sẽ mơ hồ khi chúng lệch
/// giá trị — top-level là nguồn duy nhất cho các giá trị đó, map trả về ở
/// đây chỉ chứa dữ liệu KHÔNG có ở đâu khác (đặc thù DG13/CCCD Việt Nam).
class NfcDg13Parser {
  const NfcDg13Parser._();

  static Map<String, String> parse(Uint8List dg13Bytes) {
    try {
      return _parseInternal(dg13Bytes);
    } on Dg13ParseError {
      rethrow;
    } catch (e) {
      throw Dg13ParseError('Không parse được DG13: $e');
    }
  }

  static Map<String, String> _parseInternal(Uint8List dg13Bytes) {
    final outer = ASN1Parser(dg13Bytes).nextObject();
    if (outer is! ASN1Sequence || outer.elements.isEmpty) {
      throw const Dg13ParseError('DG13 không đúng cấu trúc outer sequence');
    }

    final content = outer.elements[0];
    if (content is! ASN1Sequence) {
      throw const Dg13ParseError('DG13 thiếu content sequence (elements[0])');
    }

    final fieldSet = content.elements.whereType<ASN1Set>().firstOrNull;
    if (fieldSet == null) {
      throw const Dg13ParseError('DG13 không tìm thấy SET chứa các field');
    }

    final fields = <int, ASN1Object?>{};
    for (final entry in fieldSet.elements) {
      if (entry is! ASN1Sequence || entry.elements.isEmpty) continue;
      final numberElement = entry.elements[0];
      if (numberElement is! ASN1Integer) continue;
      fields[numberElement.intValue] =
          entry.elements.length > 1 ? entry.elements[1] : null;
    }

    final result = <String, String>{};
    void put(String key, int fieldNumber) {
      final value = _decodeStringField(fields[fieldNumber]);
      if (value != null && value.isNotEmpty) result[key] = value;
    }

    // Field 1 (idNumber), 2 (fullName), 3 (dateOfBirth), 4 (gender),
    // 5 (nationality) — bỏ qua, đã có ở top-level NfcReadResult (nguồn
    // DG1/MRZ đáng tin cậy hơn).
    put('ethnicity', 6);
    put('religion', 7);
    put('placeOfOrigin', 8);
    put('placeOfResidence', 9);
    put('personalIdentification', 10);
    put('issueDate', 11);
    // Field 12 (dateOfExpiry) — bỏ qua, đã có ở top-level NfcReadResult
    // (nguồn DG1/MRZ, kiểu DateTime chuẩn thay vì string thô).

    // Field 13: SEQUENCE lồng [tên cha, tên mẹ] — không phải chuỗi phẳng.
    final parents = fields[13];
    if (parents is ASN1Sequence) {
      if (parents.elements.isNotEmpty) {
        final father = _decodeStringField(parents.elements[0]);
        if (father != null && father.isNotEmpty) result['fatherName'] = father;
      }
      if (parents.elements.length > 1) {
        final mother = _decodeStringField(parents.elements[1]);
        if (mother != null && mother.isNotEmpty) result['motherName'] = mother;
      }
    }

    // Field 14: SEQUENCE lồng [tên vợ/chồng] — vắng mặt nếu độc thân.
    final spouse = fields[14];
    if (spouse is ASN1Sequence && spouse.elements.isNotEmpty) {
      final spouseName = _decodeStringField(spouse.elements[0]);
      if (spouseName != null && spouseName.isNotEmpty) {
        result['spouseName'] = spouseName;
      }
    }

    put('otherDocumentNumber', 15);
    // Field 16: quan sát được ở mẫu thật (chuỗi hex 16 ký tự), nghi là
    // serial/ID phần cứng — CHƯA xác nhận ý nghĩa chính thức. Giữ nguyên,
    // không map thành field nghiệp vụ cho tới khi có xác nhận.
    put('field16Unconfirmed', 16);

    return result;
  }

  static String? _decodeStringField(ASN1Object? object) {
    if (object is ASN1UTF8String) return object.utf8StringValue;
    if (object is ASN1PrintableString) return object.stringValue;
    return null;
  }
}

class Dg13ParseError implements Exception {
  final String message;
  const Dg13ParseError(this.message);

  @override
  String toString() => 'Dg13ParseError: $message';
}
