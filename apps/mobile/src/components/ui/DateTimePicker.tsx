import { DateTimePicker as ExpoDateTimePicker } from "@expo/ui/community/datetime-picker";
import { Platform } from "react-native";

export interface DateTimePickerProps {
  readonly value: Date;
  readonly mode: "date" | "time";
  readonly onDismiss: () => void;
  readonly onSelect: (value: Date) => void;
}

export function DateTimePicker(props: DateTimePickerProps) {
  return (
    <ExpoDateTimePicker
      value={props.value}
      mode={props.mode}
      display={Platform.OS === "ios" ? "spinner" : "default"}
      onDismiss={props.onDismiss}
      onValueChange={(_, value) => {
        if (Platform.OS === "android") props.onDismiss();
        props.onSelect(value);
      }}
    />
  );
}
