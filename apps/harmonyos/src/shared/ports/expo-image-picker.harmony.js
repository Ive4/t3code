import { PROVIDER_SEND_TURN_MAX_ATTACHMENTS } from "@t3tools/contracts";
import { TurboModuleRegistry } from "react-native";

export async function launchImageLibraryAsync({
  mediaTypes = ["images"],
  allowsMultipleSelection = false,
  selectionLimit = 0,
} = {}) {
  const limit = allowsMultipleSelection
    ? Math.min(
        selectionLimit || PROVIDER_SEND_TURN_MAX_ATTACHMENTS,
        PROVIDER_SEND_TURN_MAX_ATTACHMENTS,
      )
    : 1;
  const picker = TurboModuleRegistry.getEnforcing("T3AttachmentPicker");
  const selected = await picker.pickMedia(limit, mediaTypes.includes("videos"));
  if (selected.length === 0) return { canceled: true, assets: null };
  return {
    canceled: false,
    assets: selected.map(({ uri, name, type, mimeType, size, width, height }) => ({
      uri,
      type,
      mimeType,
      fileName: name,
      fileSize: size,
      width: width ?? 0,
      height: height ?? 0,
    })),
  };
}
