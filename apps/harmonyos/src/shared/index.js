import "../polyfills.js";
import "../../../mobile/src/i18n/intl-polyfills";
import "@formatjs/intl-numberformat/polyfill";
import "@formatjs/intl-numberformat/locale-data/en";
import "@formatjs/intl-numberformat/locale-data/de";
import "@formatjs/intl-numberformat/locale-data/es";
import "@formatjs/intl-numberformat/locale-data/fr";
import "@formatjs/intl-numberformat/locale-data/ja";
import "@formatjs/intl-numberformat/locale-data/ko";
import "@formatjs/intl-numberformat/locale-data/pt";
import "@formatjs/intl-numberformat/locale-data/ru";
import "@formatjs/intl-numberformat/locale-data/sv";
import "@formatjs/intl-numberformat/locale-data/zh";
import "./intl-datetimeformat.js";
import "expo";
import { TurboModuleRegistry } from "react-native";
import { installReactNativeFetch } from "./installReactNativeFetch.js";

installReactNativeFetch();

Intl.DateTimeFormat.__setDefaultTimeZone?.(
  TurboModuleRegistry.getEnforcing("T3Metadata").device().timeZone,
);
require("../../../mobile/index.ts");
