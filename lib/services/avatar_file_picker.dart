import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class PickedAvatarFile {
  const PickedAvatarFile({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

Future<PickedAvatarFile?> pickAvatarFile({ImagePicker? imagePicker}) async {
  final picker = imagePicker ?? ImagePicker();
  final image = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 88,
  );
  if (image == null) {
    return null;
  }

  return PickedAvatarFile(
    bytes: await image.readAsBytes(),
    filename: image.name,
  );
}
