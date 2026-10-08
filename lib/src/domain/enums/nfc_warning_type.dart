/// Mã cảnh báo không-fatal trong quá trình đọc. App tự map sang thông điệp
/// ngôn ngữ riêng (lib không kèm string hiển thị).
enum NfcWarningType {
  /// MRZ không có đủ 12 ký tự để lấy số định danh.
  idNumberMissing,

  /// Thẻ không công bố DG1 (MRZ) trong EF.COM.
  dg1NotDeclared,

  /// DG1 có công bố nhưng đọc lỗi.
  dg1ReadFailed,

  /// Thẻ không công bố DG2 (ảnh).
  dg2NotDeclared,

  /// DG2 có công bố nhưng không chứa dữ liệu ảnh.
  dg2NoImage,

  /// DG2 có công bố nhưng đọc lỗi.
  dg2ReadFailed,

  /// DG13 có công bố nhưng không parse được field nào.
  dg13Empty,

  /// DG13 có công bố nhưng đọc/parse lỗi.
  dg13ReadOrParseFailed,

  /// Không lấy được bằng chứng Active Authentication.
  aaFailed,
}
