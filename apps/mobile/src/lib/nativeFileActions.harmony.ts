import { TurboModuleRegistry, type TurboModule } from "react-native";

import { beginForegroundHandoff } from "./foreground-handoff";

interface NativeFileActions extends TurboModule {
  isInlinePdfAvailable?: () => boolean;
  openFile(uri: string, mimeType: string): Promise<void>;
  saveImageToLibrary(uri: string, mimeType: string, name: string): Promise<boolean>;
}

export function isInlinePdfAvailable(): boolean {
  return (
    TurboModuleRegistry.get<NativeFileActions>("T3FileActions")?.isInlinePdfAvailable?.() === true
  );
}

export function openFile(uri: string, mimeType: string): Promise<void> {
  return TurboModuleRegistry.getEnforcing<NativeFileActions>("T3FileActions").openFile(
    uri,
    mimeType,
  );
}

export async function saveLocalImage(
  uri: string,
  mimeType: string,
  name: string,
): Promise<boolean> {
  const endHandoff = beginForegroundHandoff();
  try {
    return await TurboModuleRegistry.getEnforcing<NativeFileActions>(
      "T3FileActions",
    ).saveImageToLibrary(uri, mimeType, name);
  } finally {
    endHandoff();
  }
}
