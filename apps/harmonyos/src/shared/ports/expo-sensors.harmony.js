import { DeviceEventEmitter, TurboModuleRegistry } from "react-native";

const metersPerSecondSquaredPerG = 9.80665;
let intervalMs = 100;
let nextSubscriptionId = 0;

export const Accelerometer = {
  setUpdateInterval(interval) {
    intervalMs = interval;
  },
  addListener(listener) {
    const native = TurboModuleRegistry.get("T3Accelerometer");
    const event = "T3Accelerometer:" + ++nextSubscriptionId;
    if (!native?.startWatching(event, intervalMs)) return { remove() {} };

    const subscription = DeviceEventEmitter.addListener(event, ({ x, y, z, timestamp }) =>
      listener({
        x: x / metersPerSecondSquaredPerG,
        y: y / metersPerSecondSquaredPerG,
        z: z / metersPerSecondSquaredPerG,
        timestamp: timestamp / 1_000_000_000,
      }),
    );
    return {
      remove() {
        subscription.remove();
        native.stopWatching(event);
      },
    };
  },
};
