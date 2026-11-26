import { TurboModuleRegistry } from "react-native";

const nativeStorage = TurboModuleRegistry.getEnforcing("T3SecureStorage");
export const WHEN_UNLOCKED_THIS_DEVICE_ONLY = "WHEN_UNLOCKED_THIS_DEVICE_ONLY";

function check(key, options) {
  if (typeof key !== "string" || key.length === 0 || /[^A-Za-z0-9_.-]/.test(key)) {
    throw new TypeError("Invalid secure storage key");
  }
  if (!options || Object.keys(options).length === 0) return false;
  if (
    options.keychainAccessible !== WHEN_UNLOCKED_THIS_DEVICE_ONLY ||
    Object.keys(options).length !== 1
  ) {
    throw new Error("Unsupported Harmony secure storage options.");
  }
  return true;
}

export function setItem(key, value, options) {
  if (!check(key, options)) throw new Error("Synchronous storage requires a device-only key.");
  if (typeof value !== "string") throw new TypeError("Secure storage expects a string");
  nativeStorage.setDeviceOnlyItem(key, value);
}

export async function getItemAsync(key, options) {
  return check(key, options) ? nativeStorage.getDeviceOnlyItem(key) : nativeStorage.getItem(key);
}

export async function setItemAsync(key, value, options) {
  if (check(key, options)) return setItem(key, value, options);
  if (typeof value !== "string") throw new TypeError("Secure storage expects a string");
  return nativeStorage.setItem(key, value);
}

export async function deleteItemAsync(key, options) {
  if (check(key, options)) return nativeStorage.deleteDeviceOnlyItem(key);
  return nativeStorage.deleteItem(key);
}
