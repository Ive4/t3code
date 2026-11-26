import Constants from "expo-constants";

export function getCloudConfigExtra() {
  return Constants.expoConfig?.extra;
}
