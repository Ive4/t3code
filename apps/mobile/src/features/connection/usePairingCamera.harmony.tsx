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
    if (pending.current) return;
    pending.current = true;
    await Promise.resolve()
      .then(() => TurboModuleRegistry.getEnforcing<PairingScanner>("T3PairingScanner").scan())
      .then((data) => {
        if (data !== null) onScan({ data });
      })
      .catch(() => Dialog.alert(gt("Scan QR code"), gt("Could not scan a pairing QR code.")))
      .finally(() => {
        pending.current = false;
      });
  }

  return { preview: null, scan };
}
