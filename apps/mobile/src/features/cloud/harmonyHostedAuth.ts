import { Linking } from "react-native";

export const harmonyAccountRedirect = "clerk://com.t3tools.t3code.dev.hosted-callback";

type BrowserResult = { type: "success"; url: string } | { type: "cancel" };

export async function openAuthSessionAsync(
  portal: string,
  redirect: string,
  options?: { signal?: AbortSignal },
): Promise<BrowserResult> {
  if (redirect !== harmonyAccountRedirect || new URL(portal).protocol !== "https:") {
    throw new Error("Invalid hosted account URL.");
  }
  const signal = options?.signal;
  if (signal?.aborted) return { type: "cancel" };

  return new Promise((resolve, reject) => {
    const subscription = Linking.addEventListener("url", ({ url }) => {
      if (url.split(/[?#]/, 1)[0] !== redirect) return;
      cleanup();
      resolve({ type: "success", url });
    });
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error("Hosted sign-in timed out."));
    }, 10 * 60_000);
    function cleanup() {
      clearTimeout(timeout);
      signal?.removeEventListener("abort", cancel);
      subscription.remove();
    }
    function cancel() {
      cleanup();
      resolve({ type: "cancel" });
    }
    signal?.addEventListener("abort", cancel);
    void Linking.openURL(portal).catch((error: unknown) => {
      cleanup();
      reject(error);
    });
  });
}
