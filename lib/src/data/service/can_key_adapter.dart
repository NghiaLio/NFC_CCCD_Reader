// dmrtd không export CanKey qua barrel công khai (chỉ export DBAKey/AccessKey)
// — cô lập import path nội bộ vào ĐÚNG 1 FILE này. src/proto/ không phải
// public API, có thể đổi/xoá ở bản nâng cấp dmrtd sau này mà không tăng
// version phù hợp (semver không áp dụng cho internal path).
// ignore: implementation_imports
import 'package:dmrtd/src/proto/can_key.dart' as dmrtd_internal;
import 'package:dmrtd/dmrtd.dart' show AccessKey;

AccessKey buildCanAccessKey(String can) => dmrtd_internal.CanKey(can);
