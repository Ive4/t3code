import { TurboModuleRegistry } from "react-native";

const defaultTag = "ExpoKeepAwakeDefaultTag";
const activeTags = new Set();
let pending = Promise.resolve();

function setTagActive(tag, active) {
  const operation = pending.then(async () => {
    const screen = TurboModuleRegistry.get("T3ScreenAwake");
    if (active) {
      if (activeTags.size === 0) await screen?.setKeepScreenOn(true);
      activeTags.add(tag);
    } else if (activeTags.delete(tag) && activeTags.size === 0) {
      await screen?.setKeepScreenOn(false);
    }
  });
  pending = operation.catch(() => {});
  return operation;
}

export function activateKeepAwakeAsync(tag = defaultTag) {
  return setTagActive(tag, true);
}

export function deactivateKeepAwake(tag = defaultTag) {
  return setTagActive(tag, false);
}
