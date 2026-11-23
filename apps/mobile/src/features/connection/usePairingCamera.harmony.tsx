import { useGT } from "gt-react-native";
import { useRef } from "react";
import { TurboModuleRegistry, type TurboModule } from "react-native";
import * as Dialog from "../../components/ui/Dialog";
import type { PairingCameraOptions } from "./usePairingCamera";

interface PairingScanner extends TurboModule {
  scan(): Promise<string | null>;
}

export function usePairingCamera({ onScan }: PairingCameraOptions) {
  const gt = useGT();
  const pending = useRef(false);

  async function scan() {
    const scanner = TurboModuleRegistry.get<PairingScanner>("T3PairingScanner");
    if (!scanner || pending.current) return;
    pending.current = true;
    await Promise.resolve()
      .then(() => scanner.scan())
      .then((data) => {
        if (data !== null) onScan({ data });
      })
      .catch((error: unknown) => {
        Dialog.alert(gt("Scan QR code"), error instanceof Error ? error.message : gt("Try again"));
      })
      .finally(() => {
        pending.current = false;
      });
  }

  return { preview: null, scan };
}
