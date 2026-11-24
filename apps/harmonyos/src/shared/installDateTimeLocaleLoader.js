export function installDateTimeLocaleLoader(loadAdditionalLocales) {
  const formatter = Intl.DateTimeFormat;
  if (typeof formatter.__addLocaleData !== "function") return;

  let loaded = false;
  function prepare(locales) {
    if (loaded || locales === undefined || locales === "en") return;
    loadAdditionalLocales();
    loaded = true;
  }

  const supportedLocalesOf = formatter.supportedLocalesOf;
  formatter.supportedLocalesOf = function (locales, options) {
    prepare(locales);
    return supportedLocalesOf.call(this, locales, options);
  };
  const wrapped = new Proxy(formatter, {
    apply(target, receiver, args) {
      prepare(args[0]);
      return Reflect.apply(target, receiver, args);
    },
    construct(target, args, newTarget) {
      prepare(args[0]);
      return Reflect.construct(target, args, newTarget);
    },
  });
  formatter.prototype.constructor = wrapped;
  Intl.DateTimeFormat = wrapped;

  // FormatJS's Date methods call its internal formatter directly.
  for (const method of ["toLocaleString", "toLocaleDateString", "toLocaleTimeString"]) {
    const format = Date.prototype[method];
    // oxlint-disable-next-line eslint/no-extend-native -- install the loader on FormatJS's Date entry points
    Date.prototype[method] = function (locales, options) {
      prepare(locales);
      return format.call(this, locales, options);
    };
  }
}
