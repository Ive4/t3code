import { useEffectEvent, useLayoutEffect, type PropsWithChildren } from "react";
import { DeviceEventEmitter, TurboModuleRegistry, View, type TurboModule } from "react-native";

import type { HardwareKeyboardCommand } from "../features/keyboard/hardwareKeyboardCommands";

interface KeyboardInteraction extends TurboModule {
  setKeyboardCommands(commands: ReadonlyArray<HardwareKeyboardCommand>): Promise<void>;
}

export function T3KeyboardCommands({
  children,
  enabledCommands,
  onCommand,
}: PropsWithChildren<{
  readonly enabledCommands: ReadonlyArray<HardwareKeyboardCommand>;
  readonly onCommand: (command: HardwareKeyboardCommand) => void;
}>) {
  const handleCommand = useEffectEvent((command: HardwareKeyboardCommand) => {
    if (enabledCommands.includes(command)) onCommand(command);
  });
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- listens for the enabled commands dispatched by ArkUI
  useLayoutEffect(() => {
    const listener = DeviceEventEmitter.addListener("T3KeyboardCommand", handleCommand);
    return () => listener.remove();
  }, []);

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- keeps foreground native shortcuts aligned with the current route
  useLayoutEffect(() => {
    const keyboard = TurboModuleRegistry.getEnforcing<KeyboardInteraction>("T3Interaction");
    void keyboard.setKeyboardCommands(enabledCommands).catch(() => {});
    return () => {
      void keyboard.setKeyboardCommands([]).catch(() => {});
    };
  }, [enabledCommands]);

  return <View className="flex-1">{children}</View>;
}
