import { TurboModuleRegistry } from "react-native";
export const DeviceType = { UNKNOWN: 0, PHONE: 1, TABLET: 2, DESKTOP: 3, TV: 4 };
const metadata = TurboModuleRegistry.getEnforcing("T3Metadata").device();
export const { manufacturer, modelName, osVersion } = metadata;
export const deviceType =
  { phone: DeviceType.PHONE, tablet: DeviceType.TABLET, "2in1": DeviceType.DESKTOP }[
    metadata.deviceType
  ] ?? DeviceType.UNKNOWN;
