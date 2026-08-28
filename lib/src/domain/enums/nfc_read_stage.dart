/// Mốc tiến trình THẬT của 1 phiên đọc chip — dùng để vẽ progress UI theo
/// callback [onStage], không phải timer giả lập.
enum NfcReadStage { waitingForCard, authenticating, reading, validating }
