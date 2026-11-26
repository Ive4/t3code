export function allowWebNavigation(url, isTopFrame, whitelist, callback) {
  const origin = /^([a-z][a-z\d+.-]*:(?:\/\/[^/?#]*)?)/i.exec(url)?.[1];
  if (!origin) return false;
  const allowed =
    url === "about:blank" ||
    whitelist.some((pattern) => {
      const expression = pattern
        .split("*")
        .map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
        .join(".*");
      return new RegExp("^" + expression + "$", "i").test(origin);
    });
  return allowed && (callback?.({ url, isTopFrame }) ?? true);
}
