import { TextDecoder, TextEncoder } from "@exodus/bytes/encoding-lite.js";
import "react-native-url-polyfill/auto";

globalThis.TextDecoder ??= TextDecoder;
globalThis.TextEncoder ??= TextEncoder;
