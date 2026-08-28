enum NfcFailureType {
  /// Không tìm thấy thẻ trong thời gian chờ (chưa từng kết nối được).
  timeout,

  /// Mất kết nối với thẻ giữa chừng (đã kết nối rồi mới rớt — rút thẻ sớm).
  tagLost,

  /// NFC hệ thống đang tắt.
  nfcDisabled,

  /// CAN/CCCD nhập sai (PACE auth token mismatch).
  wrongCan,

  /// Thiết lập phiên PACE thất bại vì lý do khác sai CAN.
  paceFailed,

  /// Thiết lập phiên BAC thất bại (hoặc BAC chưa được hỗ trợ).
  bacFailed,

  /// Thẻ thiếu Data Group cần thiết.
  dgMissing,

  /// Active Authentication thất bại.
  activeAuthFailed,

  /// Không phân loại được — lưới an toàn cuối cùng.
  unknown,
}
