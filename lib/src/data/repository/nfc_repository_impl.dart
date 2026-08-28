import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

import '../../domain/entities/nfc_read_input.dart';
import '../../domain/entities/nfc_read_result.dart';
import '../../domain/enums/nfc_availability_status.dart';
import '../../domain/enums/nfc_read_stage.dart';
import '../../domain/repository/nfc_repository.dart';
import '../service/nfc_chip_reader_service.dart';

class NfcRepositoryImpl implements NfcRepository {
  NfcRepositoryImpl({NfcChipReaderService? chipReaderService})
      : _chipReaderService = chipReaderService ?? NfcChipReaderService();

  final NfcChipReaderService _chipReaderService;

  @override
  Future<NfcAvailabilityStatus> checkAvailability() async {
    final availability = await FlutterNfcKit.nfcAvailability;
    return switch (availability) {
      NFCAvailability.available => NfcAvailabilityStatus.available,
      NFCAvailability.disabled => NfcAvailabilityStatus.disabled,
      NFCAvailability.not_supported => NfcAvailabilityStatus.notSupported,
    };
  }

  @override
  Future<NfcReadResult> readChip(
    NfcReadInput input, {
    void Function(NfcReadStage stage)? onStage,
  }) {
    return _chipReaderService.read(input, onStage: onStage);
  }

  @override
  Future<void> cancel() => _chipReaderService.cancel();
}
