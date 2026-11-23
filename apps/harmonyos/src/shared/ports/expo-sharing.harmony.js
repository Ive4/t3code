import { DeviceEventEmitter, TurboModuleRegistry } from "react-native";

const INCOMING_SHARE_EVENT = "T3IncomingShareChanged";
let incomingListeners = 0;

function nativeSharing() {
  return TurboModuleRegistry.get("T3Sharing");
}

function hasFileSystem() {
  return TurboModuleRegistry.get("T3FileSystem") != null;
}

function unavailable() {
  return Object.assign(new Error("Sharing is unavailable on this device."), {
    code: "ERR_UNAVAILABLE",
  });
}

export async function isAvailableAsync() {
  return hasFileSystem() && (await nativeSharing()?.isAvailableAsync()) === true;
}

export async function shareAsync(uri, options = {}) {
  const sharing = nativeSharing();
  if (!sharing || !hasFileSystem()) throw unavailable();
  await sharing.shareAsync(uri, options.mimeType ?? "");
}

export function getSharedPayloads() {
  return nativeSharing()?.getSharedPayloads() ?? [];
}

export async function getResolvedSharedPayloadsAsync() {
  return (await nativeSharing()?.getResolvedSharedPayloadsAsync()) ?? [];
}

export function clearSharedPayloads() {
  nativeSharing()?.clearSharedPayloads();
}

export function isIncomingSharingAvailable() {
  return hasFileSystem() && nativeSharing()?.isIncomingSharingAvailable() === true;
}

export function addIncomingShareListener(listener) {
  const sharing = nativeSharing();
  if (!sharing) throw unavailable();

  const subscription = DeviceEventEmitter.addListener(INCOMING_SHARE_EVENT, listener);
  try {
    if (incomingListeners === 0) sharing.startWatching();
    incomingListeners += 1;
  } catch (error) {
    subscription.remove();
    throw error;
  }

  let removed = false;
  return {
    remove() {
      if (removed) return;
      removed = true;
      subscription.remove();
      incomingListeners -= 1;
      if (incomingListeners === 0) sharing.stopWatching();
    },
  };
}
