import { useGT } from "gt-react-native";
import { useRef } from "react";

import { SecretTextInput } from "../../components/ui/SecretTextInput";
import type { SecretTextInputHandle } from "../../components/ui/SecretTextInput.types";
import { SettingsSwitchRow } from "./components/SettingsSwitchRow";

export interface HarmonyNewPassword {
  readonly password: string;
  readonly confirmation: string;
  readonly signOutOfOtherSessions: boolean;
}

export const emptyHarmonyNewPassword: HarmonyNewPassword = {
  password: "",
  confirmation: "",
  signOutOfOtherSessions: false,
};

export function canSubmitHarmonyNewPassword(password: string, confirmation: string) {
  return Boolean(password.trim()) && password === confirmation;
}

export function HarmonyNewPasswordFields(props: {
  readonly value: HarmonyNewPassword;
  readonly editable: boolean;
  readonly onChange: (value: HarmonyNewPassword) => void;
  readonly onSubmit: (confirmation: string) => void;
  readonly onFirstInputMount?: (handle: SecretTextInputHandle | null) => void;
}) {
  const gt = useGT();
  const { value, editable, onChange } = props;
  const confirmationInput = useRef<SecretTextInputHandle | null>(null);
  const newPassword = gt("New password");
  const confirmPassword = gt("Confirm password");
  return (
    <>
      <SecretTextInput
        accessibilityLabel={newPassword}
        placeholder={newPassword}
        value={value.password}
        editable={editable}
        onChangeText={(password) => onChange({ ...value, password })}
        onSubmitEditing={() => confirmationInput.current?.focus()}
        returnKeyType="next"
        onMount={props.onFirstInputMount}
      />
      <SecretTextInput
        accessibilityLabel={confirmPassword}
        placeholder={confirmPassword}
        value={value.confirmation}
        editable={editable}
        onChangeText={(confirmation) => onChange({ ...value, confirmation })}
        onSubmitEditing={props.onSubmit}
        onMount={(handle) => {
          confirmationInput.current = handle;
        }}
      />
      <SettingsSwitchRow
        label={gt("Sign out of all other devices")}
        value={value.signOutOfOtherSessions}
        disabled={!editable}
        onValueChange={(signOutOfOtherSessions) => onChange({ ...value, signOutOfOtherSessions })}
      />
    </>
  );
}
