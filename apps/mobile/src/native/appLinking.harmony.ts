import type { CreateURLOptions } from "expo-linking";
import { Linking } from "react-native";

export function createURL(
  path: string,
  { scheme = "t3code", queryParams = {}, isTripleSlashed = false }: CreateURLOptions = {},
) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(queryParams)) {
    if (value !== undefined) params.set(key, String(value));
  }
  const query = params.toString();
  const slashes = isTripleSlashed ? "///" : "//";
  return `${scheme}:${slashes}${encodeURI(path.replace(/^\//, ""))}${query ? `?${query}` : ""}`;
}

export function getInitialURL() {
  return Linking.getInitialURL();
}
