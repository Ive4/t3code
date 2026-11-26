import { useEffectEvent, useId, useLayoutEffect } from "react";
import {
  DeviceEventEmitter,
  Platform,
  requireNativeComponent,
  View,
  type ViewProps,
} from "react-native";

const NativeHarmonyClipboardPasteButton =
  String(Platform.OS) === "harmony"
    ? requireNativeComponent<ViewProps & { readonly textOnly?: boolean }>("T3ComposerPaste")
    : View;

export function HarmonyClipboardPasteButton({
  onPaste,
  size = 36,
}: {
  readonly onPaste: (text: string) => void;
  readonly size?: number;
}) {
  const id = useId();
  const receive = useEffectEvent(({ text }: { readonly text: string }) => {
    if (text) onPaste(text);
  });
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- only the mounted clipboard control receives its native tap result
  useLayoutEffect(() => {
    const subscription = DeviceEventEmitter.addListener(
      "T3ComposerPaste:" + id,
      (data: { readonly text: string }) => receive(data),
    );
    return () => subscription.remove();
  }, [id]);
  return (
    <NativeHarmonyClipboardPasteButton
      textOnly
      nativeID={id}
      collapsable={false}
      style={{ width: size, height: size, flexShrink: 0 }}
    />
  );
}
