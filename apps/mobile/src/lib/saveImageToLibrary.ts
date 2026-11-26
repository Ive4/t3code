import { Platform } from "react-native";

import { saveLocalImage } from "./nativeFileActions";

const SAVABLE_IMAGE_MIME_TYPE = /^image\/(png|jpe?g|gif|webp|heic|heif)$/i;

function baseMimeType(mimeType: string): string {
  return mimeType.split(";", 1)[0]?.trim() ?? "";
}

// Android 9 and older need a storage permission to add photos, so they keep the share sheet.
export function canSaveImageToLibrary(mimeType: string): boolean {
  return (
    SAVABLE_IMAGE_MIME_TYPE.test(baseMimeType(mimeType)) &&
    (Platform.OS === "ios" ||
      String(Platform.OS) === "harmony" ||
      (Platform.OS === "android" && Platform.Version >= 29))
  );
}

/** Returns false if the user declines the gallery save. */
export function saveImageToLibrary(uri: string, mimeType: string, name: string): Promise<boolean> {
  return saveLocalImage(uri, baseMimeType(mimeType), name);
}
