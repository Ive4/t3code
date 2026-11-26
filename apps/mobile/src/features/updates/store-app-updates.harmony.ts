import { useEffect, useState } from "react";
import { TurboModuleRegistry, type TurboModule } from "react-native";
import type { StoreAppUpdateClient } from "./store-app-updates";

interface HarmonyStoreAppUpdateClient extends StoreAppUpdateClient, TurboModule {
  isAvailable(): Promise<boolean>;
}

export function useStoreAppUpdateClient(): StoreAppUpdateClient | null {
  const [client, setClient] = useState<StoreAppUpdateClient | null>(null);
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- synchronizes availability with AppGallery and the installed certificate
  useEffect(() => {
    const native = TurboModuleRegistry.get<HarmonyStoreAppUpdateClient>("T3AppGalleryUpdates");
    if (!native) return;
    let mounted = true;
    void native.isAvailable().then(
      (available) => {
        if (available && mounted) setClient(native);
      },
      () => undefined,
    );
    return () => {
      mounted = false;
    };
  }, []);
  return client;
}
