import { requireNativeModule } from "expo";
import { useEffect, useMemo, useState } from "react";
import { AppState, Platform, TurboModuleRegistry, type TurboModule } from "react-native";
import { createMessageTimeFormatter } from "./messageTimestamp";

interface ClockFormatModule extends TurboModule {
  is24HourFormat?(): boolean;
}

const isHarmony = String(Platform.OS) === "harmony";

function systemUses24HourClock() {
  if (isHarmony)
    return TurboModuleRegistry.get<ClockFormatModule>("T3Metadata")?.is24HourFormat?.();
  if (Platform.OS !== "android") return undefined;
  return requireNativeModule<{ is24HourFormat(): boolean }>("T3NativeControls").is24HourFormat();
}

export function useMessageTimeFormatter() {
  const [is24Hour, setIs24Hour] = useState(systemUses24HourClock);
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- The OS clock preference can change while the app is in the background.
  useEffect(() => {
    if (Platform.OS !== "android" && !isHarmony) return;
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active") setIs24Hour(systemUses24HourClock());
    });
    return () => subscription.remove();
  }, []);
  return useMemo(() => createMessageTimeFormatter(is24Hour), [is24Hour]);
}
