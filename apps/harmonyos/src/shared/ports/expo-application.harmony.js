import { TurboModuleRegistry } from "react-native";
export const { nativeApplicationVersion, nativeBuildVersion, applicationName, applicationId } =
  TurboModuleRegistry.getEnforcing("T3Metadata").application();
