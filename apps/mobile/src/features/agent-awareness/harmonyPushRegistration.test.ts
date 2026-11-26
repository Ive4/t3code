import { EnvironmentId } from "@t3tools/contracts";
import { expect, it, vi } from "vite-plus/test";

import {
  createHarmonyPushRegistration,
  createHarmonyPushService,
  normalizeHarmonyPushOrigin,
  type HarmonyPushRegistrationInputs,
  type HarmonyPushRegistrationState,
} from "./harmonyPushRegistration";

const alpha = EnvironmentId.make("alpha");
const beta = EnvironmentId.make("beta");
const expiresAt = "2099-01-02T03:04:05Z";
const origin = "https://push.example.test";
const enabled: HarmonyPushRegistrationInputs = {
  environments: new Map([
    [alpha, true],
    [beta, true],
  ]),
  permission: true,
  preferences: { enabled: true, phases: { notifyOnCompletion: false } },
};

function setup() {
  let persisted: string | null = null;
  let state: HarmonyPushRegistrationState | undefined;
  let enabledToken = "push-a";
  const fetch = vi.fn<typeof globalThis.fetch>(async (url, input) => {
    if (String(url).endsWith("/login"))
      return Response.json({ accessToken: "app-bearer", expiresAt });
    if (input?.method === "GET") return Response.json({ expiresAt });
    return new Response(null, { status: 204 });
  });
  const native = {
    getPushToken: async () => enabledToken,
    signInHuaweiAccount: vi.fn(async (): Promise<string | null> => "account-code"),
  };
  const create = () =>
    createHarmonyPushRegistration({
      service: createHarmonyPushService(origin, fetch),
      read: async () => persisted,
      write: async (value) => {
        persisted = value;
      },
      native,
      onChange: (value) => {
        state = value;
      },
    });
  const registration = create();
  return {
    registration,
    create,
    fetch,
    native,
    state: () => state,
    persisted: () => persisted,
    setToken: (token: string) => {
      enabledToken = token;
    },
    writes: () =>
      fetch.mock.calls
        .filter(([, input]) => input?.method === "PUT")
        .map(([, input]) => JSON.parse(String(input?.body))),
  };
}

it("only registers opted-in scopes after Huawei sign-in and replaces a rotated push token", async () => {
  const fixture = setup();
  await fixture.registration.update(enabled);
  expect(fixture.fetch).not.toHaveBeenCalled();

  await fixture.registration.signIn();
  expect(fixture.native.signInHuaweiAccount).toHaveBeenCalledOnce();
  const [url, request] = fixture.fetch.mock.calls[0]!;
  expect(url).toBe(origin + "/v1/mobile/login");
  expect(JSON.parse(String(request?.body))).toEqual({ code: "account-code", pushToken: "push-a" });
  expect(fixture.persisted()).toContain("app-bearer");
  expect(fixture.persisted()).not.toContain("account-code");
  expect(fixture.state()?.ready).toEqual(new Set([alpha, beta]));

  fixture.setToken("push-b");
  await fixture.registration.observePushToken("push-b");
  await fixture.registration.update({ ...enabled, preferences: { enabled: false } });
  expect(fixture.writes()).toEqual([
    {
      pushToken: "push-a",
      environmentIds: [alpha, beta],
      phases: ["waiting_for_approval", "waiting_for_input", "failed"],
    },
    {
      pushToken: "push-b",
      environmentIds: [alpha, beta],
      phases: ["waiting_for_approval", "waiting_for_input", "failed"],
    },
    { pushToken: "push-b", environmentIds: [], phases: [] },
  ]);
  expect(fixture.state()?.ready).toEqual(new Set());
  expect(fixture.fetch.mock.calls.at(-1)?.[1]?.headers).toMatchObject({
    Authorization: "Bearer app-bearer",
  });
});

it("preserves authorized offline environments on restart and removes disabled or denied ones", async () => {
  const fixture = setup();
  await fixture.registration.update(enabled);
  await fixture.registration.signIn();
  fixture.setToken("push-while-closed");
  const restarted = fixture.create();

  await restarted.refresh();
  expect(fixture.fetch.mock.calls.at(-1)).toEqual([
    origin + "/v1/session",
    expect.objectContaining({ method: "GET", headers: { Authorization: "Bearer app-bearer" } }),
  ]);
  await restarted.update({
    ...enabled,
    environments: new Map([
      [alpha, undefined],
      [beta, false],
    ]),
  });
  expect(fixture.writes().at(-1)).toMatchObject({
    pushToken: "push-while-closed",
    environmentIds: [alpha],
  });

  await restarted.update({ ...enabled, environments: new Map([[beta, undefined]]) });
  expect(fixture.writes().at(-1)).toEqual({
    pushToken: "push-while-closed",
    environmentIds: [],
    phases: [],
  });
});

it("leaves the Huawei session signed out when the user cancels the system prompt", async () => {
  const fixture = setup();
  fixture.native.signInHuaweiAccount.mockResolvedValueOnce(null);
  await fixture.registration.update(enabled);
  await fixture.registration.signIn();
  expect(fixture.fetch).not.toHaveBeenCalled();
  expect(fixture.persisted()).toBeNull();
  expect(fixture.state()?.session).toBe("signedOut");
});

it("keeps an unconfirmed registration unavailable and retries it on refresh", async () => {
  const fixture = setup();
  const fetch = fixture.fetch.getMockImplementation()!;
  fixture.fetch.mockImplementation(async (url, input) =>
    input?.method === "PUT" ? new Response("unexpected response") : fetch(url, input),
  );
  await fixture.registration.update(enabled);
  await fixture.registration.signIn();
  expect(fixture.state()).toMatchObject({
    session: "signedIn",
    ready: new Set(),
    error: "registration",
  });
  fixture.fetch.mockImplementation(fetch);
  await fixture.registration.refresh();
  expect(fixture.state()).toMatchObject({ ready: new Set([alpha, beta]), error: null });
});

it("requires an HTTPS origin for the notification service", () => {
  expect(normalizeHarmonyPushOrigin("  https://push.example.test:8443/ ")).toBe(
    "https://push.example.test:8443",
  );
  expect(normalizeHarmonyPushOrigin("http://push.example.test")).toBeNull();
  expect(normalizeHarmonyPushOrigin("https://push.example.test/subpath")).toBeNull();
  expect(normalizeHarmonyPushOrigin("https://user@push.example.test")).toBeNull();
  expect(normalizeHarmonyPushOrigin("https://push.example.test?test=1")).toBeNull();
});

it("clears an invalidated session and keeps a failed sign-out retryable", async () => {
  const fixture = setup();
  await fixture.registration.update(enabled);
  await fixture.registration.signIn();

  fixture.fetch.mockRejectedValueOnce(new TypeError("offline"));
  await expect(fixture.registration.signOut()).rejects.toThrow("offline");
  expect(fixture.persisted()).toContain("app-bearer");
  expect(fixture.state()?.session).toBe("signedIn");

  fixture.fetch.mockResolvedValueOnce(new Response(null, { status: 401 }));
  await fixture.registration.refresh();
  expect(fixture.state()).toMatchObject({ session: "expired", ready: new Set() });
  expect(fixture.persisted()).toBeNull();

  await fixture.registration.signIn();
  await fixture.registration.signOut();
  expect(fixture.fetch.mock.calls.at(-1)).toEqual([
    origin + "/v1/session",
    expect.objectContaining({ method: "DELETE", headers: { Authorization: "Bearer app-bearer" } }),
  ]);
  expect(fixture.persisted()).toBeNull();
  expect(fixture.state()?.session).toBe("signedOut");
});

it("finishes the opt-out behind an in-flight registration and drops stale readiness", async () => {
  const fixture = setup();
  await fixture.registration.update(enabled);
  const { promise, resolve } = Promise.withResolvers<Response>();
  const { promise: started, resolve: start } = Promise.withResolvers<void>();
  fixture.fetch.mockImplementationOnce((url, input) => {
    expect(String(url)).toBe(origin + "/v1/mobile/login");
    expect(input?.method).toBe("POST");
    return Promise.resolve(Response.json({ accessToken: "app-bearer", expiresAt }));
  });
  fixture.fetch.mockImplementationOnce(() => {
    start();
    return promise;
  });

  const signingIn = fixture.registration.signIn();
  await started;
  const optingOut = fixture.registration.update({ ...enabled, preferences: { enabled: false } });
  expect(fixture.state()?.ready).toEqual(new Set());
  resolve(new Response(null, { status: 204 }));
  await Promise.all([signingIn, optingOut]);
  expect(fixture.writes().at(-1)).toEqual({ pushToken: "push-a", environmentIds: [], phases: [] });
  expect(fixture.state()?.ready).toEqual(new Set());
});
