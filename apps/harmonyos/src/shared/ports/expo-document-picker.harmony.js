import { PROVIDER_SEND_TURN_MAX_ATTACHMENTS } from "@t3tools/contracts";
import { TurboModuleRegistry } from "react-native";

export async function getDocumentAsync({ multiple = false } = {}) {
  const picker = TurboModuleRegistry.getEnforcing("T3AttachmentPicker");
  const assets = await picker.pickDocuments(multiple ? PROVIDER_SEND_TURN_MAX_ATTACHMENTS : 1);
  return assets.length === 0 ? { canceled: true, assets: null } : { canceled: false, assets };
}
