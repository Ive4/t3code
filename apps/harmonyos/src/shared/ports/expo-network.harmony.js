import { DeviceEventEmitter, TurboModuleRegistry } from "react-native";

const network = TurboModuleRegistry.getEnforcing("T3Network");

export function getNetworkStateAsync() {
  return network.getNetworkState();
}

export function addNetworkStateListener(listener) {
  const subscription = DeviceEventEmitter.addListener("T3NetworkStateChanged", listener);
  try {
    network.startWatching();
    return subscription;
  } catch (error) {
    subscription.remove();
    throw error;
  }
}
