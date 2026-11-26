import { requireNativeModule } from "expo";

interface NativeFileActions {
  openFile(uri: string, mimeType: string): Promise<void>;
  saveImageToLibrary(uri: string, mimeType: string, name: string): Promise<void>;
}

export function openFile(uri: string, mimeType: string): Promise<void> {
  return requireNativeModule<NativeFileActions>("T3NativeControls").openFile(uri, mimeType);
}

export async function saveLocalImage(
  uri: string,
  mimeType: string,
  name: string,
): Promise<boolean> {
  await requireNativeModule<NativeFileActions>("T3NativeControls").saveImageToLibrary(
    uri,
    mimeType,
    name,
  );
  return true;
}
