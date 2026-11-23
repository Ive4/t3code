import type { ComponentType, ReactNode } from "react";
import {
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
  type TextInputProps,
  type TextProps,
} from "react-native";

export const PAIRING_SCAN_RETICLE = { size: 150, top: 36, radius: 28 };

export function PairingScanSurface({
  light,
  active,
  disabled,
  onPress,
  scanLabel,
  tapLabel,
  instructions,
  icon,
  TextComponent = Text,
  children,
}: {
  readonly light: boolean;
  readonly active?: boolean;
  readonly disabled?: boolean;
  readonly onPress: () => void;
  readonly scanLabel: string;
  readonly tapLabel: string;
  readonly instructions: string;
  readonly icon?: ReactNode;
  readonly TextComponent?: ComponentType<TextProps>;
  readonly children?: ReactNode;
}) {
  const color = light ? "rgba(0,0,0,0.7)" : "rgba(255,255,255,0.8)";
  return (
    <Pressable
      accessibilityRole={active ? undefined : "button"}
      accessibilityLabel={active ? undefined : scanLabel}
      disabled={active || disabled}
      onPress={onPress}
      style={[styles.scanner, { backgroundColor: light ? "#e4e4e7" : "#202020" }]}
    >
      {children}
      <View pointerEvents="none" style={styles.scanOverlay}>
        <View style={[styles.reticle, { borderColor: color }]}>
          {!active && (
            <>
              {icon}
              <TextComponent style={[styles.scanHint, { color }]}>{tapLabel}</TextComponent>
            </>
          )}
        </View>
        <TextComponent style={[styles.scanInstructions, { color }]}>{instructions}</TextComponent>
      </View>
    </Pressable>
  );
}

export interface PairingFormColors {
  readonly foreground: string;
  readonly muted: string;
  readonly placeholder: string;
  readonly card: string;
  readonly border: string;
  readonly error: string;
}

export function PairingFormContent({
  scanner,
  address,
  code,
  onAddressChange,
  onCodeChange,
  onSubmit,
  editable,
  error,
  colors,
  labels,
  TextComponent = Text,
  InputComponent = TextInput,
  children,
}: {
  readonly scanner: ReactNode;
  readonly address: string;
  readonly code: string;
  readonly onAddressChange: (value: string) => void;
  readonly onCodeChange: (value: string) => void;
  readonly onSubmit: () => void;
  readonly editable?: boolean;
  readonly error: string | null;
  readonly colors: PairingFormColors;
  readonly labels: {
    readonly manual: string;
    readonly address: string;
    readonly code: string;
    readonly codePlaceholder: string;
    readonly help: string;
  };
  readonly TextComponent?: ComponentType<TextProps>;
  readonly InputComponent?: ComponentType<TextInputProps>;
  readonly children?: ReactNode;
}) {
  const inputs = [
    {
      label: labels.address,
      props: {
        keyboardType: "url",
        placeholder: "192.168.1.100:3773",
        value: address,
        onChangeText: onAddressChange,
      },
    },
    {
      label: labels.code,
      props: {
        placeholder: labels.codePlaceholder,
        returnKeyType: "go",
        value: code,
        onChangeText: onCodeChange,
        onSubmitEditing: onSubmit,
      },
    },
  ] satisfies ReadonlyArray<{ label: string; props: TextInputProps }>;

  return (
    <View collapsable={false} style={styles.body}>
      {scanner}
      <View collapsable={false} style={styles.manual}>
        <TextComponent style={[styles.sectionLabel, { color: colors.muted }]}>
          {labels.manual}
        </TextComponent>
        <View
          collapsable={false}
          style={[
            styles.card,
            { backgroundColor: colors.card, borderColor: error ? colors.error : "transparent" },
          ]}
        >
          {inputs.map(({ label, props }, index) => (
            <View key={label} collapsable={false}>
              {index > 0 && <View style={[styles.divider, { borderColor: colors.border }]} />}
              <View collapsable={false} style={styles.row}>
                <TextComponent
                  accessibilityElementsHidden
                  importantForAccessibility="no-hide-descendants"
                  style={[styles.label, { color: colors.muted }]}
                >
                  {label}
                </TextComponent>
                <InputComponent
                  {...props}
                  {...(editable === undefined ? {} : { editable })}
                  accessibilityLabel={label}
                  autoCapitalize="none"
                  autoCorrect={false}
                  placeholderTextColor={colors.placeholder}
                  textAlignVertical="center"
                  style={[styles.input, { color: colors.foreground }]}
                />
              </View>
            </View>
          ))}
        </View>
        <TextComponent
          accessibilityLiveRegion="polite"
          style={[styles.help, { color: error ? colors.error : colors.muted }]}
        >
          {error ?? labels.help}
        </TextComponent>
      </View>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  scanner: { height: 250, overflow: "hidden", borderRadius: 26 },
  scanOverlay: {
    position: "absolute",
    left: 0,
    right: 0,
    top: PAIRING_SCAN_RETICLE.top,
    alignItems: "center",
    gap: 12.25,
    paddingHorizontal: 12,
  },
  reticle: {
    width: PAIRING_SCAN_RETICLE.size,
    height: PAIRING_SCAN_RETICLE.size,
    borderRadius: PAIRING_SCAN_RETICLE.radius,
    borderWidth: 3,
    alignItems: "center",
    justifyContent: "center",
    gap: 7,
  },
  scanHint: { fontSize: 12.25, fontWeight: "500", textAlign: "center" },
  scanInstructions: { fontSize: 12.25, textAlign: "center" },
  body: { gap: 22.75 },
  manual: { gap: 7 },
  sectionLabel: { paddingHorizontal: 14, fontSize: 12.25, fontWeight: "500" },
  help: { paddingHorizontal: 14, fontSize: 12.25, lineHeight: 18.375 },
  card: { overflow: "hidden", borderWidth: 1, borderRadius: 26 },
  divider: { marginLeft: 14, borderTopWidth: 1 },
  row: {
    minHeight: 48,
    flexDirection: "row",
    alignItems: "center",
    gap: 10.5,
    paddingHorizontal: 14,
  },
  label: { width: 70, fontSize: 14, lineHeight: 23 },
  input: {
    minHeight: 48,
    flex: 1,
    alignSelf: "stretch",
    borderRadius: 0,
    borderWidth: 0,
    backgroundColor: "transparent",
    padding: 0,
    fontSize: 14,
    lineHeight: 23,
  },
});
