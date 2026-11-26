import { EnvironmentId } from "@t3tools/contracts";
import * as Schema from "effect/Schema";

import type { HarmonyNotificationPhases } from "../../persistence/mobile-preferences";
import { harmonyAlertPhasePreferences, type HarmonyAgentAlert } from "./harmonyAgentAlerts";

interface PushSession {
  readonly accessToken: string;
  readonly expiresAt: string;
}

interface SavedSession extends PushSession {
  readonly origin: string;
  readonly pushToken: string;
  readonly environmentIds: readonly EnvironmentId[];
}

interface Registration {
  readonly pushToken: string;
  readonly environmentIds: readonly EnvironmentId[];
  readonly phases: readonly HarmonyAgentAlert["phase"][];
}

export interface HarmonyPushRegistrationInputs {
  readonly environments: ReadonlyMap<EnvironmentId, boolean | undefined> | undefined;
  readonly permission: boolean | null;
  readonly preferences:
    | { readonly enabled: boolean; readonly phases?: HarmonyNotificationPhases | undefined }
    | undefined;
}

export interface HarmonyPushRegistrationState {
  readonly session: "checking" | "signedOut" | "signedIn" | "expired";
  readonly ready: ReadonlySet<EnvironmentId>;
  readonly pending: boolean;
  readonly error: "session" | "registration" | null;
}

export const initialHarmonyPushRegistrationState: HarmonyPushRegistrationState = {
  session: "checking",
  ready: new Set(),
  pending: false,
  error: null,
};

function readExpiresAt(value: unknown): string {
  if (
    typeof value === "object" &&
    value !== null &&
    "expiresAt" in value &&
    typeof value.expiresAt === "string" &&
    Number.isFinite(Date.parse(value.expiresAt))
  ) {
    return value.expiresAt;
  }
  throw new Error("Invalid push session expiry.");
}

function readSession(value: unknown): PushSession {
  if (
    typeof value === "object" &&
    value !== null &&
    "accessToken" in value &&
    typeof value.accessToken === "string" &&
    value.accessToken.length > 0
  ) {
    return { accessToken: value.accessToken, expiresAt: readExpiresAt(value) };
  }
  throw new Error("Invalid push session.");
}

function restoreSession(value: string, origin: string): SavedSession | null {
  const saved: unknown = JSON.parse(value);
  if (
    typeof saved !== "object" ||
    saved === null ||
    !("origin" in saved) ||
    saved.origin !== origin ||
    !("pushToken" in saved) ||
    typeof saved.pushToken !== "string" ||
    !saved.pushToken ||
    !("environmentIds" in saved) ||
    !Array.isArray(saved.environmentIds)
  ) {
    return null;
  }
  const environmentIds = saved.environmentIds.flatMap((id: unknown) =>
    typeof id === "string" && id ? [EnvironmentId.make(id)] : [],
  );
  return { ...readSession(saved), origin, pushToken: saved.pushToken, environmentIds };
}

class PushServiceHttpError extends Schema.TaggedError<
  PushServiceHttpError,
  {
    readonly brand: unique symbol;
  }
>()("PushServiceHttpError", { status: Schema.Number }) {
  override get message() {
    return `Push service returned HTTP ${this.status}.`;
  }
}

const isPushServiceHttpError = Schema.is(PushServiceHttpError);

function expectNoContent(response: Response): void {
  if (response.status !== 204) throw new PushServiceHttpError({ status: response.status });
}

export function normalizeHarmonyPushOrigin(value: unknown): string | null {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    const url = new URL(value.trim());
    return url.protocol === "https:" &&
      !url.username &&
      !url.password &&
      url.pathname === "/" &&
      !url.search &&
      !url.hash
      ? url.origin
      : null;
  } catch {
    return null;
  }
}

export function createHarmonyPushService(
  origin: string,
  fetch: typeof globalThis.fetch = globalThis.fetch,
) {
  async function request<A>(
    path: string,
    method: string,
    decode: (response: Response) => A,
    token?: string,
    body?: Registration | { readonly code: string; readonly pushToken: string },
  ): Promise<Awaited<A>> {
    const headers: Record<string, string> = {};
    if (token) headers.Authorization = `Bearer ${token}`;
    if (body) headers["Content-Type"] = "application/json";
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10_000);
    try {
      const response = await fetch(origin + path, {
        method,
        headers,
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        signal: controller.signal,
        credentials: "omit",
        redirect: "error",
      });
      if (!response.ok) throw new PushServiceHttpError({ status: response.status });
      return await decode(response);
    } finally {
      clearTimeout(timeout);
    }
  }

  return {
    origin,
    login: (code: string, pushToken: string) =>
      request(
        "/v1/mobile/login",
        "POST",
        async (response) => readSession(await response.json()),
        undefined,
        { code, pushToken },
      ),
    status: (token: string) =>
      request(
        "/v1/session",
        "GET",
        async (response) => readExpiresAt(await response.json()),
        token,
      ),
    setRegistration: (token: string, input: Registration) =>
      request("/v1/mobile/registration", "PUT", expectNoContent, token, input),
    logout: (token: string) => request("/v1/session", "DELETE", expectNoContent, token),
  };
}

export function createHarmonyPushRegistration(options: {
  readonly service: ReturnType<typeof createHarmonyPushService>;
  readonly read: () => Promise<string | null>;
  readonly write: (value: string | null) => Promise<void>;
  readonly native: {
    readonly getPushToken: () => Promise<string>;
    readonly signInHuaweiAccount: () => Promise<string | null>;
  };
  readonly onChange: (state: HarmonyPushRegistrationState) => void;
}) {
  const { service } = options;
  let saved: SavedSession | null = null;
  let session: HarmonyPushRegistrationState["session"] = "checking";
  let error: HarmonyPushRegistrationState["error"] = null;
  let inputs: HarmonyPushRegistrationInputs = {
    environments: undefined,
    permission: null,
    preferences: undefined,
  };
  let queue = Promise.resolve();
  let active = 0;
  let pushToken: string | undefined;
  let tokenRevision = 0;
  let tokenStatus: "needed" | "failed" | "current" = "needed";
  let confirmed: string | undefined;
  let attempted: string | undefined;

  function desired(): Registration | null {
    if (!saved || !inputs.preferences) return null;
    const token = pushToken ?? saved.pushToken;
    if (!inputs.preferences.enabled || inputs.permission === false) {
      return { pushToken: token, environmentIds: [], phases: [] };
    }
    if (inputs.permission === null || inputs.environments === undefined) return null;

    const phases = Object.keys(harmonyAlertPhasePreferences)
      .filter((phase): phase is HarmonyAgentAlert["phase"] =>
        Object.hasOwn(harmonyAlertPhasePreferences, phase),
      )
      .filter(
        (phase) => inputs.preferences?.phases?.[harmonyAlertPhasePreferences[phase]] !== false,
      );

    const previouslyAuthorized = new Set(saved.environmentIds);
    const environmentIds = [...inputs.environments]
      .filter(([id, allowed]) => allowed ?? previouslyAuthorized.has(id))
      .map(([id]) => id)
      .sort();
    return environmentIds.length === 0 || phases.length === 0
      ? { pushToken: token, environmentIds: [], phases: [] }
      : { pushToken: token, environmentIds, phases };
  }

  function publish() {
    const registration = desired();
    const ready = new Set(
      registration && JSON.stringify(registration) === confirmed ? registration.environmentIds : [],
    );
    options.onChange({ session, ready, pending: active > 0, error });
  }

  function enqueue<A>(operation: () => Promise<A>): Promise<A> {
    active++;
    publish();
    const result = queue.then(operation).finally(() => {
      active--;
      publish();
    });
    queue = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  }

  async function clear(next: "expired" | "signedOut") {
    await options.write(null);
    saved = null;
    session = next;
    error = null;
    confirmed = undefined;
    attempted = undefined;
  }

  async function load() {
    if (session === "checking") {
      const raw = await options.read();
      let stale = false;
      if (raw !== null) {
        try {
          saved = restoreSession(raw, service.origin);
        } catch {
          stale = true;
        }
        stale ||= saved === null;
      }
      if (stale) await options.write(null);
      session = saved ? "signedIn" : "signedOut";
    }
    if (saved && Date.parse(saved.expiresAt) <= Date.now()) await clear("expired");
  }

  async function refreshNativeToken() {
    tokenStatus = "failed";
    const revision = tokenRevision;
    const token = (await options.native.getPushToken()).trim();
    if (!token) throw new Error("Push Kit did not return a token.");
    if (revision === tokenRevision) pushToken = token;
    tokenStatus = "current";
    return pushToken ?? token;
  }

  async function reconcile() {
    await load();
    if (
      saved &&
      inputs.preferences?.enabled &&
      inputs.permission === true &&
      tokenStatus === "needed"
    ) {
      // Push Kit may have rotated the token while this instance was stopped.
      await refreshNativeToken().catch(() => {});
    }
    const registration = desired();
    if (!saved || registration === null) return;
    const signature = JSON.stringify(registration);
    if (signature === confirmed || signature === attempted) return;
    attempted = signature;
    try {
      await service.setRegistration(saved.accessToken, registration);
      const updated = {
        ...saved,
        pushToken: registration.pushToken,
        environmentIds: registration.environmentIds,
      };
      await options.write(JSON.stringify(updated));
      saved = updated;
      confirmed = signature;
      error = null;
    } catch (failure) {
      if (isPushServiceHttpError(failure) && failure.status === 401) {
        await clear("expired");
      } else {
        confirmed = undefined;
        error = "registration";
      }
    }
  }

  function sync() {
    return enqueue(async () => {
      try {
        await reconcile();
      } catch {
        error = "session";
      }
    });
  }

  return {
    update(next: HarmonyPushRegistrationInputs) {
      inputs = next;
      return sync();
    },
    refresh() {
      return enqueue(async () => {
        try {
          await load();
          if (!saved) return;
          const expiresAt = await service.status(saved.accessToken);
          if (expiresAt !== saved.expiresAt) {
            saved = { ...saved, expiresAt };
            await options.write(JSON.stringify(saved));
          }
          if (Date.parse(expiresAt) <= Date.now()) {
            await clear("expired");
            return;
          }
          error = null;
        } catch (failure) {
          if (isPushServiceHttpError(failure) && failure.status === 401) {
            await clear("expired").catch(() => {
              error = "session";
            });
          } else {
            error = "session";
          }
          return;
        }

        if (tokenStatus === "failed") tokenStatus = "needed";
        attempted = undefined;
        await reconcile().catch(() => {
          error = "registration";
        });
      });
    },
    observePushToken(value: unknown) {
      if (typeof value !== "string" || !value.trim()) return Promise.resolve();
      tokenRevision++;
      pushToken = value.trim();
      tokenStatus = "current";
      attempted = undefined;
      return sync();
    },
    signIn() {
      return enqueue(async () => {
        await load();
        if (saved) return;
        const pushToken = await refreshNativeToken();
        const code = await options.native.signInHuaweiAccount();
        if (code === null) return;
        const login = await service.login(code, pushToken);
        const authenticated = { ...login, origin: service.origin, pushToken, environmentIds: [] };
        try {
          await options.write(JSON.stringify(authenticated));
        } catch (failure) {
          await service.logout(login.accessToken).catch(() => {});
          throw failure;
        }
        saved = authenticated;
        session = "signedIn";
        error = null;
        await reconcile();
      });
    },
    signOut() {
      return enqueue(async () => {
        await load();
        if (saved) {
          try {
            await service.logout(saved.accessToken);
          } catch (failure) {
            if (!(isPushServiceHttpError(failure) && failure.status === 401)) throw failure;
          }
        }
        await clear("signedOut");
      });
    },
  };
}
