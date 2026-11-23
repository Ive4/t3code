import type { ComponentType } from "react";
import { StyleSheet, Text, type TextProps } from "react-native";

export function ThreadListTitle({
  TextComponent = Text,
  style,
  ...props
}: TextProps & {
  readonly className?: string;
  readonly TextComponent?: ComponentType<TextProps & { readonly className?: string }>;
}) {
  return <TextComponent numberOfLines={2} {...props} style={[styles.title, style]} />;
}

const styles = StyleSheet.create({
  title: { fontSize: 14, lineHeight: 21 },
});
