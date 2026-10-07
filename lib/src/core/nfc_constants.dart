/// AID (Application Identifier) chuẩn ICAO eMRTD/ePassport — dùng khi cấu
/// hình `com.apple.developer.nfc.readersession.iso7816.select-identifiers`
/// trên iOS. Xem README mục cấu hình native.
class NfcConstants {
  static const String icaoMrtdAid = 'A0000002471001';
  static const String keyAccessDataNFCIos =
      "3134300d060804007f0007020202020101300f060a04007f000702020302020201013012060a04007f0007020204020202010202010d";
}
