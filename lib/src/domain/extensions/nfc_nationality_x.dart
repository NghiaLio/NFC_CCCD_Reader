/// Nhãn hiển thị cho mã quốc tịch ICAO alpha-3 (VD: `'VNM'`). CCCD Việt Nam
/// hầu như luôn trả về `'VNM'` — chỉ ánh xạ đúng trường hợp này sang tiếng
/// Việt; mã khác (hộ chiếu nước ngoài, khi BAC được triển khai) giữ nguyên mã
/// gốc, vì package không có/không tự bịa bảng tra ISO 3166-1 alpha-3 đầy đủ.
extension NfcNationalityPresentation on String {
  String get nationalityLabel => this == 'VNM' ? 'Việt Nam' : this;
}
