// Created by Crt Vavros, copyright © 2022 ZeroPass. All rights reserved.
import 'dart:typed_data';

import 'package:dmrtd/dmrtd.dart';

import 'access_key.dart';
import 'bac.dart';
import 'dba_key.dart';
import 'iso7816/iso7816.dart';
import 'iso7816/icc.dart';
import 'iso7816/response_apdu.dart';

import '../com/com_provider.dart';
import '../lds/df1/df1.dart';
import '../lds/tlv.dart';
import '../utils.dart';

import 'package:dmrtd/extensions.dart';
import 'package:logging/logging.dart';

import 'pace.dart';

class MrtdApiError implements Exception {
  final String message;
  final StatusWord? code;
  const MrtdApiError(this.message, {this.code});
  @override
  String toString() => "MRTDApiError: $message";
}

/// Defines ICAO 9303 MRTD standard API to
/// communicate and send commands to MRTD.
/// TODO: Add ComProvider onConnected notifier and reset _maxRead to _defaultReadLength on new connection
class MrtdApi {
  static const int challengeLen = 8; // 8 bytes
  ICC icc;

  MrtdApi(ComProvider com) : icc = ICC(com);

  // See: Section 4.1 https://www.icao.int/publications/Documents/9303_p10_cons_en.pdf
  static const _defaultSelectP2 =
      ISO97816_SelectFileP2.returnFCP | ISO97816_SelectFileP2.returnFMD;
  final _log = Logger("mrtd.api");
  static const int _defaultReadLength =
      2048; // 256 = expect maximum number of bytes. TODO: in production set it to 224 - JMRTD
  int _maxRead = _defaultReadLength;
  static const int _readAheadLength =
      8; // Number of bytes to read at the start of file to determine file length.
  Future<void> Function()? _reinitSession;

  /// Sends active authentication command to MRTD with [challenge].
  /// [challenge] must be 8 bytes long.
  /// MRTD returns signature of size [sigLength] or of arbitrarily size if [sigLength] is 256.
  /// Can throw [ICCError] if [challenge] is not 8 bytes or [sigLength] is wrong signature length.
  /// Can throw [ComProviderError] in case connection with MRTD is lost.
  Future<Uint8List> activeAuthenticate(final Uint8List challenge,
      {int sigLength = 256}) async {
    assert(challenge.length == challengeLen);
    _log.debug("Sending AA command with challenge=${challenge.hex()}");
    return await icc.internalAuthenticate(data: challenge, ne: sigLength);
  }

  /// Initializes Secure Messaging session via BAC protocol using [keys].
  /// Can throw [ICCError] if provided wrong keys.
  /// Can throw [ComProviderError] in case connection with MRTD is lost.
  Future<void> initSessionViaBAC(final DBAKey keys) async {
    _log.debug("Initiating SM session using BAC protocol");
    await BAC.initSession(dbaKeys: keys, icc: icc);
    _reinitSession = () async {
      _log.debug("Re-initiating SM session using BAC protocol");
      icc.sm = null;
      await BAC.initSession(dbaKeys: keys, icc: icc);
    };
  }

  /// Initializes Secure Messaging session via PACE protocol using [keys].
  /// Can throw [ICCError] if provided wrong keys.
  /// Can throw [ComProviderError] in case connection with MRTD is lost.
  Future<void> initSessionViaPACE(
      final AccessKey accessKey, EfCardAccess efCardAccess) async {
    _log.debug("Initiating SM session using PACE protocol (only DBA for now)");
    await PACE.initSession(
        accessKey: accessKey, icc: icc, efCardAccess: efCardAccess);
    _reinitSession = () async {
      _log.debug("Re-initiating SM session using PACE protocol");
      icc.sm = null;
      await PACE.initSession(
          accessKey: accessKey, icc: icc, efCardAccess: efCardAccess);
    };
  }

  /// Selects eMRTD application (DF1) applet.
  /// Can throw [ICCError] if command is sent to invalid MRTD document.
  /// Can throw [ComProviderError] in case connection with MRTD is lost.
  Future<void> selectEMrtdApplication() async {
    _log.debug("Selecting eMRTD application");
    await icc.selectFileByDFName(dfName: DF1.AID, p2: _defaultSelectP2);
  }

  /// Selects Master File (MF).
  /// Can throw [ICCError] if command is sent to invalid MRTD document.
  /// Can throw [ComProviderError] in case connection with MRTD is lost.
  Future<void> selectMasterFile() async {
    _log.debug("Selecting root Master File");

    // List of possible P1 values
    List<int> p1Values = [
      0x04,
    ];
    // List<int> p1Values = [0x00, 0x01, 0x02, 0x04, 0x08];
    // List<int> p1Values = [0x00, 0x01, 0x02, 0x08];
    // List of possible P2 values

    List<int> p2Values = [0x00, 0x02, 0x04, 0x08, 0x0C];
    // List<int> p2Values = [0x00];
    for (int i = 0; i < p1Values.length; i++) {
      for (int j = 0; j < p2Values.length; j++) {
        int p1 = p1Values[i];
        int p2 = p2Values[j];
        try {
          print(
              'Trying P1: ${p1.toRadixString(16).padLeft(2, '0').toUpperCase()}, P2: ${p2.toRadixString(16).padLeft(2, '0').toUpperCase()}');
          await icc.selectFile(
            cla: ISO7816_CLA.NO_SM, p1: p1, // P1
            p2: p2, // P2
          );

          _log.warning(
              'Success with P1: ${p1.toRadixString(16).padLeft(2, '0').toUpperCase()}, P2: ${p2.toRadixString(16).padLeft(2, '0').toUpperCase()}');
          break;
        } catch (e) {
          print(
              'Error with P1: ${p1.toRadixString(16).padLeft(2, '0').toUpperCase()}, P2: ${p2.toRadixString(16).padLeft(2, '0').toUpperCase()} - Error: $e');
        }
      }
    }
  }

  /// Returns raw EF file bytes of selected DF identified by [fid] from MRTD.
  /// Can throw [ICCError] in case when file doesn't exist, read errors or
  /// SM session is not established but required to read file.
  /// Can throw [ComProviderError] in case connection with MRTD is lost.
  Future<Uint8List> readFile(final int fid) async {
    _log.debug("Reading file fid=0x${Utils.intToBin(fid).hex()}");
    if (fid > 0xFFFF) {
      throw MrtdApiError("Invalid fid=0x${Utils.intToBin(fid).hex()}");
    }

    // Select EF file first
    final efId = Uint8List(2);
    ByteData.view(efId.buffer).setUint16(0, fid);
    await icc.selectEF(efId: efId, p2: _defaultSelectP2);

    // Read chunk of file to obtain file length
    final chunk1 = await icc.readBinary(offset: 0, ne: _readAheadLength);
    final dtl = TLV.decodeTagAndLength(chunk1.data!);

    // Read the rest of the file
    final length = dtl.length.value - (chunk1.data!.length - dtl.encodedLen);
    final chunk2 =
        await _readBinary(offset: chunk1.data!.length, length: length);

    final rawFile = Uint8List.fromList(chunk1.data! + chunk2);
    assert(rawFile.length == dtl.encodedLen + dtl.length.value);
    return rawFile;
  }

  /// Returns raw EF file bytes of selected DF identified by short file identifier [sfid] from MRTD.
  /// Can throw [ICCError] in case when file doesn't exist, read errors or
  /// SM session is not established but required to read file.
  /// Can throw [ComProviderError] in case connection with MRTD is lost.
  Future<Uint8List> readFileBySFI(int sfi) async {
    _log.debug("Reading file sfi=0x${sfi.hex()}");
    sfi |= 0x80;
    if (sfi > 0x9F) {
      throw ArgumentError.value(sfi, null, "Invalid SFI value");
    }

    // Read chunk of file to obtain file length
    final chunk1 =
        await icc.readBinaryBySFI(sfi: sfi, offset: 0, ne: _readAheadLength);
    final dtl = TLV.decodeTagAndLength(chunk1.data!);

    // Read the rest of the file
    final length = dtl.length.value - (chunk1.data!.length - dtl.encodedLen);
    final chunk2 =
        await _readBinary(offset: chunk1.data!.length, length: length);

    final rawFile = Uint8List.fromList(chunk1.data! + chunk2);
    assert(rawFile.length == dtl.encodedLen + dtl.length.value);
    return rawFile;
  }

  /// Hàm giảm _maxRead khi gặp lỗi
  void _reduceMaxRead() {
    if (_maxRead > 1) {
      _maxRead = (_maxRead ~/ 2).clamp(1, _defaultReadLength);
      _log.info("Reduced _maxRead to $_maxRead");
    }
  }

  /// Reads [length] long fragment of file starting at [offset].
  Future<Uint8List> _readBinary(
      {required int offset, required int length}) async {
    var data = Uint8List(0);
    while (length > 0) {
      int nRead = length;
      if (length > _maxRead) {
        nRead = _maxRead;
      }

      _log.debug(
          "_readBinary: offset=$offset nRead=$nRead remaining=$length maxRead=$_maxRead");
      try {
        ResponseAPDU rapdu;
        if (offset > 0x7FFF) {
          // extended read binary
          rapdu = await icc.readBinaryExt(offset: offset, ne: nRead);
        } else {
          if (offset + nRead > 0x7FFF) {
            // Do not overlap offset 32 767 with even READ BINARY command
            nRead = 0x7FFF - offset;
          }
          rapdu = await icc.readBinary(offset: offset, ne: nRead);
        }

        if (rapdu.status.sw1 == StatusWord.sw1SuccessWithRemainingBytes) {
          // This should probably happen only in case of calling
          // command GET STATUS, which we don't call here.
          // We log it for tracing purpose.
          _log.debug(
              "Received ${rapdu.data?.length ?? 0} byte(s), ${rapdu.status.description()}");
        } else if (rapdu.status == StatusWord.unexpectedEOF) {
          _log.warning(rapdu.status.description());
          _reduceMaxRead();
        } else if (rapdu.status == StatusWord.possibleCorruptedData) {
          _log.warning("Part of received data chunk my be corrupted");
        } else if (rapdu.status.isError()) {
          // Just making sure if an error has occured we still have valid session
          _log.warning(
              "An error ${rapdu.status} has occurred while reading file but have received some data. Re-initializing SM session and trying to continue normally.");
          await _reinitSession?.call();
        }

        if (rapdu.data != null) {
          data = Uint8List.fromList(data + rapdu.data!);
          offset += rapdu.data!.length;
          length -= rapdu.data!.length;
        } else {
          _log.warning("No data received when trying to read binary");
        }
      } on ICCError catch (e) {
        // thrown on _readBinary error when no data is received.
        if (e.sw == StatusWord.wrongLength && _maxRead != 1) {
          // if _maxRead == 1 then we tried all possible lengths and failed, so this check should throw us out of the loop
          _reduceMaxRead();
        } else if (e.sw.sw1 == StatusWord.sw1WrongLengthWithExactLength) {
          _log.warning(
              "Reducing max read to ${e.sw.sw2} byte(s) due to wrong length error");
          _maxRead = e.sw.sw2;
        } else {
          _maxRead = _defaultReadLength;
          throw MrtdApiError(
              "An error has occurred while trying to read file chunk.",
              code: e.sw);
        }
        if (e.sw.isError()) {
          // Just a sanity check as ICCError is thrown only on error
          _log.info("Re-initializing SM session due to read binary error");
          await _reinitSession?.call();
        }
      }
    }

    // Verify total received data size is not greater than
    // requested and remove excess data.
    // Some passports e.g.: Slovenian on SW:0x6282 (unexpectedEOF)
    // add possible wrong pad data: 0x000080 instead of 0x800000.
    if (length < 0) {
      final newSize = data.length - length.abs();
      _log.warning(
          "Total read data size is greater than requested, removing last ${length.abs()} byte(s)");
      _log.debug(
          "  Requested size:$newSize byte(s) actual size:${data.length} byte(s)");
      data = data.sublist(0, newSize);
    }

    return data;
  }

  // void _reduceMaxRead() {
  //   if (_maxRead > 224) {
  //     _maxRead = 224; // JMRTD lib's default read size
  //   } else if (_maxRead > 160) {
  //     // Some passports can't handle more then 160 bytes per read
  //     _maxRead = 160;
  //   } else if (_maxRead > 128) {
  //     _maxRead = 128;
  //   } else if (_maxRead > 96) {
  //     _maxRead = 96;
  //   } else if (_maxRead > 64) {
  //     _maxRead = 64;
  //   } else if (_maxRead > 32) {
  //     _maxRead = 32;
  //   } else if (_maxRead > 16) {
  //     _maxRead = 16;
  //   } else if (_maxRead > 8) {
  //     _maxRead = 8;
  //   } else {
  //     _maxRead = 1; // last resort try to read 1 byte at the time
  //   }
  //   _log.info("Max read changed to: $_maxRead");
  // }
}
