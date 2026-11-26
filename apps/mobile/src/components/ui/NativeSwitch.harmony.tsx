import { Pressable, View } from "react-native";

import type { ThemedSwitchProps } from "./NativeSwitch.types";
import { useControlTheme } from "./useControlTheme";

export function NativeSwitch(props: ThemedSwitchProps) {
  const { colors } = useControlTheme();
  const checked = Boolean(props.value);
  const track = colors[checked ? "--color-switch-active-track" : "--color-switch-inactive-track"];
  const thumb = colors[checked ? "--color-switch-active-thumb" : "--color-switch-inactive-thumb"];

  return (
    <Pressable
      accessibilityHint={props.accessibilityHint}
      accessibilityLabel={props.accessibilityLabel}
      accessibilityRole="switch"
      accessibilityState={{ checked, disabled: Boolean(props.disabled) }}
      className="min-h-12 min-w-13 items-center justify-center"
      disabled={props.disabled}
      onPress={() => props.onValueChange?.(!checked)}
      style={props.style}
      testID={props.testID}
    >
      <View
        pointerEvents="none"
        className="h-8 w-13 justify-center rounded-full border-2 px-0.5"
        style={{
          backgroundColor: track,
          borderColor: checked ? track : thumb,
          opacity: props.disabled ? 0.45 : 1,
        }}
      >
        <View
          className={
            checked ? "size-6 self-end rounded-full" : "ml-1 size-4 self-start rounded-full"
          }
          style={{ backgroundColor: thumb }}
        />
      </View>
    </Pressable>
  );
}
