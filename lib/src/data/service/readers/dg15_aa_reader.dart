import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dmrtd/dmrtd.dart';

import '../../../domain/entities/nfc_warning.dart';
import '../../../domain/enums/aa_evidence_status.dart';
import '../../../domain/enums/nfc_trace_step.dart';
import '../../../domain/enums/nfc_warning_type.dart';
import '../lifecycle/nfc_trace_session.dart';
import '../result/nfc_result_assembler.dart';
import 'dg_reader_helper.dart';

/// Đọc Data Group 15 và thực hiện xác thực chủ động (Active Authentication - AA).
///
/// Sinh ngẫu nhiên CSPRNG nonce challenge, gửi cho chip ký số qua lệnh
/// `activeAuthenticate`, và trích xuất SubjectPublicKey để gửi backend xác thực.
class Dg15AaReader {
  const Dg15AaReader();

  Future<AaResult> read({
    required Passport passport,
    required EfCOM efCom,
    required NfcTraceSession trace,
    required List<NfcWarning> warnings,
  }) async {
    if (!efCom.dgTags.contains(EfDG15.TAG)) {
      return (
        dg15Bytes: null,
        challenge: null,
        signature: null,
        publicKeyBytes: null,
        algorithm: null,
        status: AaEvidenceStatus.notSupported,
      );
    }

    final stopwatch = Stopwatch()..start();
    trace.emit(NfcTraceStep.readDg15Aa);

    try {
      final dg15 = await passport.readEfDG15();
      final dg15Bytes = dg15.toBytes();
      final challenge = generateAaChallenge();
      final signature = await passport.activeAuthenticate(challenge);
      stopwatch.stop();

      final publicKeyBytes = dg15.aaPublicKey.rawSubjectPublicKey();
      final algorithm = describeAaAlgorithm(dg15.aaPublicKey.type);

      trace.emit(
        NfcTraceStep.readDg15Aa,
        bytes: signature.lengthInBytes,
        detail:
            '${stopwatch.elapsedMilliseconds}ms, challenge=${fingerprint(challenge)} sig=${fingerprint(signature)}',
      );

      return (
        dg15Bytes: dg15Bytes,
        challenge: challenge,
        signature: signature,
        publicKeyBytes: publicKeyBytes,
        algorithm: algorithm,
        status: AaEvidenceStatus.captured,
      );
    } catch (e) {
      DgReaderHelper.handleDgReadError(
        step: NfcTraceStep.readDg15Aa,
        warningType: NfcWarningType.aaFailed,
        error: e,
        trace: trace,
        warnings: warnings,
      );
      return (
        dg15Bytes: null,
        challenge: null,
        signature: null,
        publicKeyBytes: null,
        algorithm: null,
        status: AaEvidenceStatus.failed,
      );
    }
  }

  /// Sinh nonce 8-byte CSPRNG ngẫu nhiên cho Active Authentication challenge.
  static Uint8List generateAaChallenge() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(Passport.aaChallengeLen, (_) => random.nextInt(256)),
    );
  }

  /// Fingerprint 1 chiều để đối chiếu các lần quét trong log chẩn đoán (không lộ PII).
  static String fingerprint(Uint8List bytes) =>
      crypto.sha256.convert(bytes).toString().substring(0, 12);

  static String describeAaAlgorithm(AAPublicKeyType type) => switch (type) {
        AAPublicKeyType.RSA => 'RSA',
        AAPublicKeyType.ECC => 'EC',
      };
}
