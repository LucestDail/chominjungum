import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// ML Kit 한국어 OCR (이미지 파일·갤러리).
class OcrService {
  OcrService._();

  static final _recognizer = TextRecognizer(script: TextRecognitionScript.korean);
  static final _picker = ImagePicker();

  static Future<String> recognizeFile(String filePath) async {
    final input = InputImage.fromFilePath(filePath);
    final result = await _recognizer.processImage(input);
    return result.text.trim();
  }

  static Future<String?> pickAndRecognizeGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return null;
    return recognizeFile(x.path);
  }

  static Future<String> recognizePngBytes(List<int> pngBytes, {required int width, required int height}) async {
    final tmp = await Directory.systemTemp.createTemp('ocr_');
    final f = File('${tmp.path}/stroke.png');
    await f.writeAsBytes(pngBytes, flush: true);
    try {
      return await recognizeFile(f.path);
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  static Future<void> dispose() async {
    await _recognizer.close();
  }
}
