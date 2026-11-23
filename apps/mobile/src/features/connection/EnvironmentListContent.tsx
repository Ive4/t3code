import type { ComponentType, ReactNode } from "react";
import { StyleSheet, Text, View, type TextProps, type ViewProps } from "react-native";

export function EnvironmentListCard({
  color,
  ViewComponent = View,
  children,
}: {
  readonly color?: string;
  readonly ViewComponent?: ComponentType<ViewProps>;
  readonly children: ReactNode;
}) {
  return (
    <ViewComponent
      collapsable={false}
      style={[styles.card, color ? { backgroundColor: color } : undefined]}
    >
      {children}
    </ViewComponent>
  );
}

export function EnvironmentIdentity({
  name,
  address,
  leading,
  foreground,
  muted,
  TextComponent = Text,
}: {
  readonly name: string;
  readonly address: string;
  readonly leading?: ReactNode;
  readonly foreground?: string;
  readonly muted?: string;
  readonly TextComponent?: ComponentType<TextProps & { readonly className?: string }>;
}) {
  return (
    <>
      <View style={styles.heading}>
        {leading}
        <TextComponent
          numberOfLines={1}
          className="font-t3-bold text-foreground"
          style={[styles.title, foreground ? { color: foreground, fontWeight: "700" } : undefined]}
        >
          {name}
        </TextComponent>
      </View>
      {address.trim() ? (
        <TextComponent
          numberOfLines={1}
          className="text-foreground-muted"
          style={[styles.address, muted ? { color: muted } : undefined]}
        >
          {address}
        </TextComponent>
      ) : null}
    </>
  );
}

const styles = StyleSheet.create({
  card: { overflow: "hidden", borderRadius: 24 },
  heading: { flexDirection: "row", alignItems: "center", gap: 5.25 },
  title: { minWidth: 0, flexShrink: 1, fontSize: 14, lineHeight: 17.5 },
  address: { fontSize: 10.5, lineHeight: 14 },
});
