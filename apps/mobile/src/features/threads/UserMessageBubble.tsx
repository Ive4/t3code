import type { ReactNode } from "react";
import { StyleSheet, View, type ColorValue, type ViewStyle } from "react-native";

export function UserMessageBubble({
  color,
  style,
  children,
}: {
  readonly color: ColorValue;
  readonly style?: ViewStyle;
  readonly children: ReactNode;
}) {
  return <View style={[styles.bubble, { backgroundColor: color }, style]}>{children}</View>;
}

const styles = StyleSheet.create({
  bubble: { minWidth: 0, borderRadius: 20 },
});
