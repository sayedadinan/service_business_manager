import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';

// Load image as Uint8List
Future<Uint8List> loadImage(String path) async {
  final ByteData data = await rootBundle.load(path);
  return data.buffer.asUint8List();
}
