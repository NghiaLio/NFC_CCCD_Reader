import '../enums/nfc_read_stage.dart';

/// % tiến trình gợi ý cho progress bar — dùng chung để tránh mỗi màn UI tự
/// định nghĩa lại 1 bảng số khác nhau (bug thật đã gặp ở bản gốc: 2 file UI
/// tự định nghĩa trùng bảng, sửa 1 nơi quên nơi kia).
extension NfcReadStageProgress on NfcReadStage {
  double get progressValue => switch (this) {
        NfcReadStage.waitingForCard => 0.25,
        NfcReadStage.authenticating => 0.5,
        NfcReadStage.reading => 0.75,
        NfcReadStage.validating => 0.95,
      };
}
