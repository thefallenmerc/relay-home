import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models.dart';

abstract class AppStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PreferencesStorage implements AppStorage {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String key, String value) async {
    final success = await (await SharedPreferences.getInstance()).setString(
      key,
      value,
    );
    if (!success) throw StateError('Could not save changes on this device.');
  }
}

String encodeDevices(List<RelayDevice> devices) =>
    jsonEncode(devices.map((d) => d.toJson()).toList());
List<RelayDevice> decodeDevices(String? text) {
  if (text == null) return [];
  final values = jsonDecode(text) as List;
  return values
      .map((v) => RelayDevice.fromJson(Map<String, dynamic>.from(v as Map)))
      .toList();
}

class RelayImageService {
  final ImagePicker _picker = ImagePicker();
  Future<String?> importImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (image == null) return null;
    final docs = await getApplicationDocumentsDirectory();
    final folder = Directory('${docs.path}/relay_images');
    await folder.create(recursive: true);
    final extension = image.path.split('.').last.toLowerCase();
    final safeExtension =
        ['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(extension)
        ? extension
        : 'jpg';
    final target =
        '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.$safeExtension';
    await image.saveTo(target);
    return target;
  }
}
