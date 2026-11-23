import { TurboModuleRegistry } from "react-native";
const interaction = TurboModuleRegistry.getEnforcing("T3Interaction");
export const ImpactFeedbackStyle = {
  Light: "light",
  Medium: "medium",
  Heavy: "heavy",
  Rigid: "rigid",
  Soft: "soft",
};
export const NotificationFeedbackType = { Success: "success", Warning: "warning", Error: "error" };
export function impactAsync(style = ImpactFeedbackStyle.Medium) {
  return interaction.vibrate({ light: 12, medium: 20, heavy: 30, rigid: 25, soft: 9 }[style] ?? 20);
}
export function notificationAsync(type = NotificationFeedbackType.Success) {
  return interaction.vibrate({ success: 20, warning: 30, error: 45 }[type] ?? 20);
}
export function selectionAsync() {
  return interaction.vibrate(8);
}
