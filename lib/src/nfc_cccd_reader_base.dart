import 'dart:async';

import 'package:meta/meta.dart';

import 'data/repository/nfc_repository_impl.dart';
import 'data/service/nfc_chip_reader_service.dart';
import 'domain/entities/nfc_failure.dart';
import 'domain/entities/nfc_read_input.dart';
import 'domain/entities/nfc_read_result.dart';
import 'domain/enums/nfc_availability_status.dart';
import 'domain/enums/nfc_read_stage.dart';
import 'domain/repository/nfc_repository.dart';

abstract interface class NfcCccdReader {
  /// Khởi tạo instance mặc định (dùng flutter_nfc_kit + dmrtd thật).
  factory NfcCccdReader({
    /// Hook log tuỳ chọn — KHÔNG bao giờ nhận PII/CAN/challenge/signature thật,
    /// chỉ nhận thông điệp đã được rút gọn/ẩn danh sẵn từ bên trong package.
    void Function(String message)? logSink,
    Duration connectTimeout,
  }) = NfcCccdReaderBase;

  /// Kiểm tra NFC hệ thống: available / disabled / notSupported.
  Future<NfcAvailabilityStatus> checkAvailability();

  /// Đọc 1 phiên chip MRTD. Ném [NfcFailure] khi lỗi (không bao giờ để lọt
  /// exception thô từ dmrtd/flutter_nfc_kit ra ngoài package).
  ///
  /// [onStage] được gọi đúng thời điểm từng bước THẬT bắt đầu — dùng để vẽ
  /// progress UI, không phải timer giả lập.
  Future<NfcReadResult> read(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
  });

  /// Biến thể Stream cho state management theo kiểu reactive (Bloc/Riverpod
  /// StreamProvider...). Emit các `NfcReadStage` khi tiến trình thay đổi, rồi
  /// đóng stream: thành công → không emit thêm gì, caller `await` chính
  /// `Future` trả về từ hàm này để lấy `NfcReadResult`; lỗi → stream đóng kèm
  /// error qua `addError`, đồng thời Future cũng throw cùng [NfcFailure].
  ///
  /// Dùng khi cần lắng nghe tiến trình mà không muốn truyền callback lồng.
  Stream<NfcReadStage> get stageStream;

  /// Huỷ phiên đọc đang chạy (ngắt kết nối NFC giữa chừng).
  Future<void> cancel();

  /// Giải phóng tài nguyên (đóng stream nội bộ). Gọi khi không còn dùng nữa.
  void dispose();
}

class NfcCccdReaderBase implements NfcCccdReader {
  NfcCccdReaderBase({
    void Function(String message)? logSink,
    Duration connectTimeout = const Duration(seconds: 20),
  }) : _repository = NfcRepositoryImpl(
          chipReaderService: NfcChipReaderService(
            connectTimeout: connectTimeout,
            logSink: logSink,
          ),
        );

  /// Cho phép inject repository giả trong test (không cần thiết bị NFC thật).
  @visibleForTesting
  NfcCccdReaderBase.withRepository(this._repository);

  final NfcRepository _repository;
  final _stageController = StreamController<NfcReadStage>.broadcast();

  @override
  Future<NfcAvailabilityStatus> checkAvailability() =>
      _repository.checkAvailability();

  @override
  Future<NfcReadResult> read(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
  }) {
    return _repository.readChip(
      input,
      onStage: (stage) {
        _stageController.add(stage);
        onStage?.call(stage);
      },
    );
  }

  @override
  Stream<NfcReadStage> get stageStream => _stageController.stream;

  @override
  Future<void> cancel() => _repository.cancel();

  @override
  void dispose() => _stageController.close();
}
