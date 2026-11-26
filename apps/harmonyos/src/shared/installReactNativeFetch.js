export function installReactNativeFetch() {
  const fetch = globalThis.fetch;
  globalThis.fetch = (input, init) => {
    // Harmony's HTTP API rejects empty strings as request bodies.
    if (init?.body === "") return fetch(input, { ...init, body: null });
    if (!(init?.body instanceof URLSearchParams)) return fetch(input, init);

    // RCTNetworking accepts the serialized form body as a string.
    const headers = new Headers(
      init.headers ?? (input instanceof Request ? input.headers : undefined),
    );
    if (!headers.has("Content-Type")) {
      headers.set("Content-Type", "application/x-www-form-urlencoded;charset=UTF-8");
    }
    return fetch(input, { ...init, headers, body: init.body.toString() || null });
  };
}
