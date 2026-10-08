import 'dart:async';

import 'package:meta/meta.dart';

import 'data/repository/nfc_repository_impl.dart';
import 'data/service/nfc_chip_reader_service.dart';
import 'domain/entities/nfc_failure.dart';
import 'domain/entities/nfc_read_input.dart';
import 'domain/entities/nfc_read_result.dart';
import 'domain/entities/nfc_trace_event.dart';
import 'domain/enums/nfc_availability_status.dart';
import 'domain/enums/nfc_read_stage.dart';
import 'domain/repository/nfc_repository.dart';

abstract interface class NfcCccdReader {
  /// Khởi tạo instance mặc định (dùng flutter_nfc_kit + dmrtd thật).
  factory NfcCccdReader({
    Duration connectTimeout,
  }) = NfcCccdReaderBase;

  /// Kiểm tra NFC hệ thống: available / disabled / notSupported.
  Future<NfcAvailabilityStatus> checkAvailability();

  /// Đọc 1 phiên chip MRTD. Ném [NfcFailure] khi lỗi (không bao giờ để lọt
  /// exception thô từ dmrtd/flutter_nfc_kit ra ngoài package).
  ///
  /// [onStage] được gọi đúng thời điểm từng bước THẬT bắt đầu — dùng để vẽ
  /// progress UI, không phải timer giả lập.
  ///
  /// [onTrace] nhận breadcrumb chi tiết (mỗi bước 1 [NfcTraceEvent]) — dùng
  /// cho log/Sentry. Nếu không truyền, vẫn có thể lắng nghe qua [traceStream].
  Future<NfcReadResult> read(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  });

  /// Stream các `NfcReadStage` khi tiến trình thay đổi (mốc THÔ cho progress
  /// bar). Đóng stream: thành công → không emit thêm; lỗi → `addError`, đồng
  /// thời `Future` của [read] cũng throw cùng [NfcFailure].
  Stream<NfcReadStage> get stageStream;

  /// Stream breadcrumb chi tiết — mỗi bước đọc phát 1 [NfcTraceEvent] (kèm
  /// `sessionId`, SW1/SW2, độ dài byte, chi tiết đã sanitize — KHÔNG kèm PII).
  /// App hứng stream này, gom thêm thông tin thiết bị (OS, model) rồi đẩy lên
  /// Sentry/Crashlytics.
  Stream<NfcTraceEvent> get traceStream;

  /// Huỷ phiên đọc đang chạy (ngắt kết nối NFC giữa chừng).
  Future<void> cancel();

  /// Giải phóng tài nguyên (đóng stream nội bộ). Gọi khi không còn dùng nữa.
  void dispose();
}

class NfcCccdReaderBase implements NfcCccdReader {
  NfcCccdReaderBase({
    Duration connectTimeout = const Duration(seconds: 20),
  }) : _repository = NfcRepositoryImpl(
          chipReaderService: NfcChipReaderService(
            connectTimeout: connectTimeout,
          ),
        );

  /// Cho phép inject repository giả trong test (không cần thiết bị NFC thật).
  @visibleForTesting
  NfcCccdReaderBase.withRepository(this._repository);

  final NfcRepository _repository;
  final _stageController = StreamController<NfcReadStage>.broadcast();
  final _traceController = StreamController<NfcTraceEvent>.broadcast();

  @override
  Future<NfcAvailabilityStatus> checkAvailability() =>
      _repository.checkAvailability();

  @override
  Future<NfcReadResult> read(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
    void Function(NfcTraceEvent event)? onTrace,
  }) {
    return _repository.readChip(
      input,
      onStage: (stage) {
        _stageController.add(stage);
        onStage?.call(stage);
      },
      onTrace: (event) {
        _traceController.add(event);
        onTrace?.call(event);
      },
    );
  }

  @override
  Stream<NfcReadStage> get stageStream => _stageController.stream;

  @override
  Stream<NfcTraceEvent> get traceStream => _traceController.stream;

  @override
  Future<void> cancel() => _repository.cancel();

  @override
  void dispose() {
    _stageController.close();
    _traceController.close();
  }
}
