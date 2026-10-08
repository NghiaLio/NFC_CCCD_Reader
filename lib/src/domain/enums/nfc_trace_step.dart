/// Mốc breadcrumb chi tiết của 1 phiên đọc — mỗi bước phát 1 [NfcTraceEvent].
///
/// Tách riêng khỏi [NfcReadStage] (mốc thô cho progress bar UI): trace step
/// mịn hơn, phát cho đúng từng DG, kèm SW/độ dài dữ liệu — dùng cho log/
/// Sentry, không dùng để vẽ progress.
enum NfcTraceStep {
  /// `read()` được gọi, phiên bắt đầu (đã cấp `sessionId`).
  started,

  /// Đang chờ thẻ vào vùng NFC.
  connecting,

  /// Đã kết nối được thẻ ISO-7816.
  connected,

  /// Bắt đầu thiết lập phiên an toàn (PACE/BAC).
  sessionStart,

  /// Phiên an toàn đã thiết lập, đọc được EF.COM.
  sessionEstablished,

  /// Đang đọc EF.COM.
  readEfCom,

  /// Đang đọc DG1 (MRZ).
  readDg1,

  /// Đang đọc DG2 (ảnh).
  readDg2,

  /// Đang đọc DG13 (dữ liệu mở rộng CCCD).
  readDg13,

  /// Đang đọc DG15 + Active Authentication.
  readDg15Aa,

  /// Phiên thành công, trả về `NfcReadResult`.
  completed,

  /// Phiên thất bại (kèm SW/root cause ở event).
  failed,
}
