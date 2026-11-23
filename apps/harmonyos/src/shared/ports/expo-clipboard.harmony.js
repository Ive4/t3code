import { TurboModuleRegistry } from "react-native";
const interaction = TurboModuleRegistry.getEnforcing("T3Interaction");
export function getStringAsync() {
  return interaction.getClipboardText();
}
export function setStringAsync(text) {
  return interaction.setClipboardText(text);
}
