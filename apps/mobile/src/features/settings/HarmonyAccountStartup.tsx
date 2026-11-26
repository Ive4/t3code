import { useGT } from "gt-react-native";
import { useEffect, useRef, useState } from "react";
import { View } from "react-native";

import { AppActivityIndicator } from "../../components/ui/AppActivityIndicator";
import { AppText } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";

const CHECK_WAIT_MS = 8_000;

export function HarmonyAccountStartup(props: { readonly reload: () => Promise<void> }) {
  const gt = useGT();
  const [waiting, setWaiting] = useState(true);
  const [retrying, setRetrying] = useState(false);
  const pendingRetry = useRef(false);

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- caps the initial spinner while Clerk retries in the background
  useEffect(() => {
    const timer = setTimeout(() => setWaiting(false), CHECK_WAIT_MS);
    return () => clearTimeout(timer);
  }, []);

  async function retry() {
    if (pendingRetry.current) return;
    pendingRetry.current = true;
    setRetrying(true);
    try {
      await props.reload();
    } catch {
      // A failed check stays on the same error screen and can be retried again.
    } finally {
      pendingRetry.current = false;
      setRetrying(false);
    }
  }

  return (
    <View className="flex-1 items-center justify-center gap-4 px-6">
      {waiting ? (
        <>
          <AppActivityIndicator />
          <AppText>{gt("Checking")}</AppText>
        </>
      ) : (
        <>
          <AppText accessibilityRole="alert" textRole="body" className="text-center">
            {gt("Could not connect to T3 Account. Check your connection and try again.")}
          </AppText>
          <Button
            label={gt("Try again")}
            tone="primary"
            loading={retrying}
            onPress={() => void retry()}
          />
        </>
      )}
    </View>
  );
}
