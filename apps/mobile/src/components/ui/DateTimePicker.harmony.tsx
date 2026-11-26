import { useGT } from "gt-react-native";
import { useEffect, useEffectEvent, useRef } from "react";
import { TurboModuleRegistry, type TurboModule } from "react-native";

import type { DateTimePickerProps } from "./DateTimePicker";
import { alert } from "./Dialog";
import { applyHarmonyDateTimeSelection } from "./dateTimePickerSelection";

interface NativeDateTimePicker extends TurboModule {
  pick(mode: DateTimePickerProps["mode"], localTimestamp: number): Promise<number | null>;
}

export function DateTimePicker(props: DateTimePickerProps) {
  const gt = useGT();
  const request = useRef<Promise<number | null> | undefined>(undefined);
  const start = useEffectEvent(async () => {
    const native = TurboModuleRegistry.getEnforcing<NativeDateTimePicker>("T3DateTimePicker");
    return native.pick(props.mode, props.value.getTime());
  });
  const finish = useEffectEvent((selection: number | null, failed = false) => {
    const value = applyHarmonyDateTimeSelection(props.value, props.mode, selection);
    if (value) props.onSelect(value);
    props.onDismiss();
    if (failed) alert(gt("Date and time"), gt("Try again."));
  });

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- presents the native dialog once per mount and discards results after navigation away
  useEffect(() => {
    let mounted = true;
    request.current ??= start();
    void request.current.then(
      (selection) => {
        if (mounted) finish(selection);
      },
      () => {
        if (mounted) finish(null, true);
      },
    );
    return () => {
      mounted = false;
    };
  }, []);

  return null;
}
