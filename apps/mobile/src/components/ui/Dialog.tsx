import { msg } from "gt-react-native";
import { Alert, Platform } from "react-native";

import { m } from "../../i18n/messages";
import type { ConfirmDialogRequest, TextInputDialogRequest } from "./Dialog.types";

export type { ConfirmDialogRequest, TextInputDialogRequest } from "./Dialog.types";

export function alert(...[title, message, buttons, options]: Parameters<typeof Alert.alert>): void {
  const actions =
    String(Platform.OS) === "harmony" && !buttons?.length ? [{ text: m(msg("OK")) }] : buttons;
  Alert.alert(title, message, actions, options);
}

export function confirm(request: ConfirmDialogRequest): void {
  Alert.alert(request.title, request.message, [
    { text: request.cancelText ?? m(msg("Cancel")), style: "cancel", onPress: request.onCancel },
    {
      text: request.confirmText,
      style: request.destructive ? "destructive" : "default",
      onPress: request.onConfirm,
    },
  ]);
}

export function prompt(request: TextInputDialogRequest): void {
  Alert.prompt(
    request.title,
    request.message,
    [
      { text: request.cancelText ?? m(msg("Cancel")), style: "cancel", onPress: request.onCancel },
      { text: request.confirmText, onPress: (value) => request.onConfirm(value ?? "") },
    ],
    "plain-text",
    request.initialValue,
  );
}

export function Host() {
  return null;
}
