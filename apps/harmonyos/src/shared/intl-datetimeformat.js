import "@formatjs/intl-datetimeformat/polyfill";
import "@formatjs/intl-datetimeformat/add-all-tz";
import "@formatjs/intl-datetimeformat/locale-data/en";
import { installDateTimeLocaleLoader } from "./installDateTimeLocaleLoader.js";

// Load the full set for explicit locales so FormatJS can match regional fallbacks.
installDateTimeLocaleLoader(() => {
  require("@formatjs/intl-datetimeformat/locale-data/en-CA");
  require("@formatjs/intl-datetimeformat/locale-data/de");
  require("@formatjs/intl-datetimeformat/locale-data/es");
  require("@formatjs/intl-datetimeformat/locale-data/fr");
  require("@formatjs/intl-datetimeformat/locale-data/ja");
  require("@formatjs/intl-datetimeformat/locale-data/ko");
  require("@formatjs/intl-datetimeformat/locale-data/pt");
  require("@formatjs/intl-datetimeformat/locale-data/ru");
  require("@formatjs/intl-datetimeformat/locale-data/sv");
  require("@formatjs/intl-datetimeformat/locale-data/zh");
});
