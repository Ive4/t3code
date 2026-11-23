import { TurboModuleRegistry } from "react-native";

const nativeStorage = TurboModuleRegistry.getEnforcing("T3SecureStorage");
export const WHEN_UNLOCKED_THIS_DEVICE_ONLY = "WHEN_UNLOCKED_THIS_DEVICE_ONLY";

function check(key, options) {
  if (typeof key !== "string" || key.length === 0 || /[^A-Za-z0-9_.-]/.test(key)) {
    throw new TypeError("Invalid secure storage key");
  }
  if (options && Object.keys(options).length > 0) {
    throw new Error("Harmony secure storage supports the default accessibility mode.");
  }
}

export async function getItemAsync(key, options) {
  check(key, options);
  return nativeStorage.getItem(key);
}

export async function setItemAsync(key, value, options) {
  check(key, options);
  if (typeof value !== "string") throw new TypeError("Secure storage expects a string");
  return nativeStorage.setItem(key, value);
}

export async function deleteItemAsync(key, options) {
  check(key, options);
  return nativeStorage.deleteItem(key);
}
