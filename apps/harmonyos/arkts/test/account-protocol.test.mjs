import * as NodeAssert from "node:assert/strict";
import * as NodeCrypto from "node:crypto";
import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeTest from "node:test";

const source = new URL("../entry/src/main/ets/client/AccountProtocol.ets", import.meta.url);
const loader = NodeModule.registerHooks({
  load(url, context, nextLoad) {
    if (url !== source.href) return nextLoad(url, context);
    return {
      format: "module",
      shortCircuit: true,
      source: NodeModule.stripTypeScriptTypes(NodeFS.readFileSync(source, "utf8")),
    };
  },
});
const {
  ACCOUNT_REDIRECT_URL,
  AccountSessionExpiredError,
  HostedAccountSession,
  matchesAccountRedirect,
  clerkFapiUrl,
} = await import(source.href);
loader.deregister();

const redirect = ACCOUNT_REDIRECT_URL + "/finish";
const issuer = "https://fixture.clerk.example";
const browserUrl = "https://fixture.accounts.example/sign-in";
const template = "relay template";
const templatePath = "/client/sessions/sess_first/tokens/relay%20template";
const profilePath = "/me?_method=PATCH&_clerk_session_id=sess_first";
const activeSessionsPath = "/me/sessions/active?_clerk_session_id=sess_first";
const revokeOtherSessionPath = "/me/sessions/sess_second/revoke?_clerk_session_id=sess_first";
const startTime = 100;
const verifier = "a".repeat(64);
const challenge = NodeCrypto.createHash("sha256").update(verifier).digest("base64url");
const client = (id = "user_first", status = "active") => ({
  object: "client",
  last_active_session_id: "sess_other",
  sessions: [
    { id: "sess_other", status: "active", user: { id: "user_other" } },
    {
      id: "sess_first",
      status,
      user: {
        id,
        first_name: "First",
        last_name: "User",
        primary_email_address_id: "email_primary",
        email_addresses: [
          { id: "email_other", email_address: "other@fixture.example" },
          { id: "email_primary", email_address: "primary@fixture.example" },
        ],
      },
    },
  ],
});

function fixture(options = {}) {
  const calls = [];
  let now = startTime;
  let saved = options.saved;
  let pending = options.pending;
  let outcome;
  const store = {
    read: async () => saved,
    save: async (next) => {
      saved = next;
    },
    clear: async () => {
      saved = undefined;
    },
    readAttempt: async () => pending,
    saveAttempt: (next) => {
      pending = next;
    },
    consumeAttempt: (state) => {
      if (pending?.proof.state !== state) return false;
      pending = undefined;
      return true;
    },
    clearAttempt: () => {
      pending = undefined;
    },
  };
  const session = new HostedAccountSession(
    issuer,
    template,
    redirect,
    store,
    async (request) => {
      calls.push(request);
      const override = outcome?.(request);
      if (override) return await override;
      if (request.path === "/client" && request.method === "GET") {
        return {
          status: 200,
          payload: { response: client() },
          clientToken: request.clientToken ? "restored-client" : "anonymous-client",
        };
      }
      if (request.path === "/client/hosted_auth") {
        return {
          status: 200,
          payload: { response: { object: "hosted_auth", url: browserUrl } },
          clientToken: "hosted-client",
        };
      }
      if (request.path === "/client") {
        return { status: 200, payload: { response: client() }, clientToken: "first-client" };
      }
      if (request.path === "/client/sessions/sess_first/touch") {
        return {
          status: 200,
          payload: { response: client().sessions[1] },
          clientToken: "active-client",
        };
      }
      if (request.path === templatePath) {
        return {
          status: 200,
          payload: { object: "token", jwt: "example.relay.jwt" },
          clientToken: "refreshed-client",
        };
      }
      if (request.path === "/client/sessions/sess_first/remove") return { status: 204 };
      NodeAssert.fail("Unexpected fixture request: " + request.path);
    },
    async () => ({ state: "state-original", verifier, challenge }),
    () => now,
  );
  return {
    session,
    calls,
    store,
    now: (next) => {
      now = next;
    },
    reply: (next) => {
      outcome = next;
    },
    redeemCount: () =>
      calls.filter((call) => call.method === "POST" && call.path === "/client").length,
  };
}

const callback = `${redirect}?state=state-original&rotating_token_nonce=once%2Dnonce&created_session_id=sess_first`;

NodeTest.test(
  "hosted auth checks exact scheme, host and path before allowing a callback to redeem",
  async () => {
    const f = fixture();
    NodeAssert.equal(matchesAccountRedirect(callback, redirect), true);
    NodeAssert.equal(
      matchesAccountRedirect(`${ACCOUNT_REDIRECT_URL}?state=state-original`, ACCOUNT_REDIRECT_URL),
      true,
    );
    await f.session.start("sign-in");
    const invalid = [
      callback.replace("clerk:", "https:"),
      callback.replace(".hosted-callback", ".hosted-callback.evil.example"),
      callback.replace(".hosted-callback", ".hosted-callback:443"),
      callback.replace("/finish?", "/finish/?"),
      callback.replace("/finish?", "/%66inish?"),
      callback.replace("/finish?", "/else/../finish?"),
      callback.replace("://", "://user@"),
      callback.replace("state-original", "wrong-state"),
      callback.replace("&rotating_token_nonce=once%2Dnonce", ""),
      callback.replace("&created_session_id=sess_first", ""),
      callback + "&state=state-original",
      callback.replace("once%2Dnonce", "%E0%A4%A"),
    ];
    for (const candidate of invalid) {
      await NodeAssert.rejects(f.session.complete(candidate));
      NodeAssert.equal(f.redeemCount(), 0);
    }
    NodeAssert.equal((await f.session.complete(callback)).sessionId, "sess_first");
    await NodeAssert.rejects(f.session.complete(callback));
    NodeAssert.equal(f.redeemCount(), 1);
  },
);

NodeTest.test(
  "an expired, cancelled, absent or already in-flight attempt is rejected before exchange",
  async () => {
    const expired = fixture();
    await NodeAssert.rejects(expired.session.complete(callback));
    await expired.session.start("sign-up");
    expired.now(startTime + 10 * 60_000);
    await NodeAssert.rejects(expired.session.complete(callback));
    NodeAssert.equal(expired.redeemCount(), 0);

    const cancelled = fixture();
    await cancelled.session.start("sign-in");
    cancelled.session.cancel();
    await NodeAssert.rejects(cancelled.session.complete(callback));
    NodeAssert.equal(cancelled.redeemCount(), 0);

    const f = fixture();
    await f.session.start("sign-in");
    const redemption = Promise.withResolvers();
    const requested = Promise.withResolvers();
    f.reply(({ method, path }) => {
      if (method !== "POST" || path !== "/client") return;
      requested.resolve();
      return redemption.promise;
    });
    const completing = f.session.complete(callback);
    const failure = NodeAssert.rejects(completing);
    await requested.promise;
    await NodeAssert.rejects(f.session.complete(callback));
    f.session.cancel();
    redemption.resolve({
      status: 200,
      payload: { response: client() },
      clientToken: "ignored-client",
    });
    await failure;
    NodeAssert.equal(f.redeemCount(), 1);
    NodeAssert.equal(await f.store.read(), undefined);
  },
);

NodeTest.test(
  "uses the native Clerk PKCE exchange, activates only the returned session and refreshes the relay template",
  async () => {
    const { session, calls, store } = fixture();
    NodeAssert.equal(await session.start("sign-up"), browserUrl);
    NodeAssert.deepEqual(calls[1], {
      method: "POST",
      path: "/client/hosted_auth",
      clientToken: "anonymous-client",
      body: {
        redirect_url: redirect,
        code_challenge: challenge,
        mode: "sign-up",
        state: "state-original",
      },
    });
    NodeAssert.deepEqual(await session.complete(callback), {
      userId: "user_first",
      sessionId: "sess_first",
      displayName: "First User",
      firstName: "First",
      lastName: "User",
      email: "primary@fixture.example",
    });
    NodeAssert.deepEqual(calls[2], {
      method: "POST",
      path: "/client",
      clientToken: "hosted-client",
      body: { _method: "GET", rotating_token_nonce: "once-nonce", code_verifier: verifier },
    });
    NodeAssert.deepEqual(calls[3], {
      method: "POST",
      path: "/client/sessions/sess_first/touch",
      clientToken: "first-client",
      body: { intent: "select_session" },
    });
    NodeAssert.equal(await session.readRelayToken(), "example.relay.jwt");
    NodeAssert.equal(calls[4].path, templatePath);
    NodeAssert.equal(calls[4].clientToken, "active-client");
    NodeAssert.equal((await store.read()).clientToken, "refreshed-client");
    NodeAssert.equal(Object.values(await store.read()).includes("example.relay.jwt"), false);
    await session.signOut();
    NodeAssert.equal(calls[5].path, "/client/sessions/sess_first/remove");
    NodeAssert.equal(calls[5].clientToken, "refreshed-client");
    NodeAssert.equal(await store.read(), undefined);
    await NodeAssert.rejects(session.readRelayToken());
  },
);

NodeTest.test(
  "resumes a browser callback after a cold start and erases its one-time proof before exchange",
  async () => {
    const original = fixture();
    await original.session.start("sign-in");
    const pending = await original.store.readAttempt();
    NodeAssert.equal(pending.issuer, issuer);
    const relaunched = fixture({ pending });
    NodeAssert.equal(await relaunched.session.restore(), undefined);
    NodeAssert.equal((await relaunched.store.readAttempt()).proof.verifier, verifier);
    relaunched.reply(async ({ method, path }) => {
      if (method !== "POST" || path !== "/client") return { status: 503 };
      NodeAssert.equal(await relaunched.store.readAttempt(), undefined);
      return { status: 503 };
    });
    await NodeAssert.rejects(relaunched.session.complete(callback));
    await NodeAssert.rejects(relaunched.session.complete(callback));
    NodeAssert.equal(relaunched.redeemCount(), 1);

    original.session.cancel();
    NodeAssert.equal(await original.store.readAttempt(), undefined);
  },
);

NodeTest.test(
  "restores only the saved identity and clears revoked or cross-account sessions",
  async () => {
    const saved = {
      issuer,
      clientToken: "saved-client",
      sessionId: "sess_first",
      userId: "user_first",
    };
    const f = fixture({ saved });
    NodeAssert.deepEqual(await f.session.restore(), {
      userId: "user_first",
      sessionId: "sess_first",
      displayName: "First User",
      firstName: "First",
      lastName: "User",
      email: "primary@fixture.example",
    });
    NodeAssert.equal(f.calls[0].clientToken, "saved-client");
    NodeAssert.equal((await f.store.read()).clientToken, "restored-client");
    for (const reply of [
      { status: 401 },
      { status: 200, payload: { response: client("user_second") } },
      { status: 200, payload: { response: client("user_first", "expired") } },
    ]) {
      const invalid = fixture({ saved });
      invalid.reply(() => reply);
      NodeAssert.equal(await invalid.session.restore(), undefined);
      NodeAssert.equal(await invalid.store.read(), undefined);
    }
    const otherIssuer = fixture({ saved: { ...saved, issuer: "https://other.fixture.example" } });
    NodeAssert.equal(await otherIssuer.session.restore(), undefined);
    NodeAssert.equal(otherIssuer.calls.length, 0);
    f.reply(() => ({ status: 401 }));
    await NodeAssert.rejects(f.session.readRelayToken());
    NodeAssert.equal(await f.store.read(), undefined);
  },
);

NodeTest.test(
  "network errors preserve the saved account for retry and late tokens cannot survive sign-out",
  async () => {
    const saved = {
      issuer,
      clientToken: "saved-client",
      sessionId: "sess_first",
      userId: "user_first",
    };
    const f = fixture({ saved });
    f.reply(() => Promise.reject(new Error("offline fixture")));
    await NodeAssert.rejects(f.session.restore(), /offline fixture/);
    NodeAssert.deepEqual(await f.store.read(), saved);
    f.reply(undefined);
    NodeAssert.equal((await f.session.restore()).userId, "user_first");

    const requested = Promise.withResolvers();
    const reply = Promise.withResolvers();
    f.reply(({ path }) => {
      if (path !== templatePath) return;
      requested.resolve();
      return reply.promise;
    });
    const token = NodeAssert.rejects(f.session.readRelayToken());
    await requested.promise;
    const signedOut = f.session.signOut();
    reply.resolve({ status: 200, payload: { jwt: "late.relay.jwt" }, clientToken: "late-client" });
    await token;
    await signedOut;
    NodeAssert.equal(await f.store.read(), undefined);
    NodeAssert.equal(f.calls.at(-1).clientToken, "restored-client");
    await NodeAssert.rejects(f.session.readRelayToken());
  },
);

NodeTest.test("keeps the native FAPI query version and session scope", () => {
  const result = new URL(clerkFapiUrl(issuer, "/client/sessions/sess_first/remove"));
  NodeAssert.equal(result.origin, issuer);
  NodeAssert.equal(result.pathname, "/v1/client/sessions/sess_first/remove");
  NodeAssert.equal(result.searchParams.get("_is_native"), "1");
  NodeAssert.equal(result.searchParams.get("__clerk_api_version"), "2026-08-20");
  NodeAssert.equal(result.searchParams.get("_clerk_js_version"), "6.42.3");
});

NodeTest.test("updates only edited profile fields and uses the rotated credential", async () => {
  const f = fixture();
  await f.session.start("sign-in");
  const identity = await f.session.complete(callback);
  f.reply(({ path }) => {
    if (path !== profilePath) return;
    return {
      status: 200,
      payload: {
        response: { ...client().sessions[1].user, object: "user", last_name: "林" },
      },
      clientToken: "profile-client",
    };
  });

  NodeAssert.deepEqual(await f.session.updateProfileName(identity, { lastName: " 林 " }), {
    ...identity,
    lastName: "林",
    displayName: "First 林",
  });
  NodeAssert.deepEqual(f.calls.at(-1), {
    method: "POST",
    path: profilePath,
    body: { last_name: "林" },
    clientToken: "active-client",
  });
  NodeAssert.equal((await f.store.read()).clientToken, "profile-client");
  await f.session.readRelayToken();
  NodeAssert.equal(f.calls.at(-1).clientToken, "profile-client");
});

NodeTest.test("clears a profile name using an empty Clerk form value", async () => {
  const f = fixture();
  await f.session.start("sign-in");
  const identity = await f.session.complete(callback);
  f.reply(({ path }) => {
    if (path !== profilePath) return;
    return {
      status: 200,
      payload: {
        ...client().sessions[1].user,
        object: "user",
        first_name: null,
        last_name: null,
      },
    };
  });

  NodeAssert.deepEqual(
    await f.session.updateProfileName(identity, { firstName: " ", lastName: "" }),
    { ...identity, firstName: "", lastName: "", displayName: identity.email },
  );
  NodeAssert.deepEqual(f.calls.at(-1).body, { first_name: "", last_name: "" });
});

NodeTest.test("binds a profile edit to the active user and session", async () => {
  const f = fixture();
  await f.session.start("sign-in");
  const identity = await f.session.complete(callback);
  const callCount = f.calls.length;
  for (const obsolete of [
    { ...identity, sessionId: "sess_old" },
    { ...identity, userId: "user_other" },
  ]) {
    await NodeAssert.rejects(
      f.session.updateProfileName(obsolete, { firstName: "Late" }),
      AccountSessionExpiredError,
    );
  }
  NodeAssert.equal(f.calls.length, callCount);

  f.reply(({ path }) => {
    if (path !== profilePath) return;
    return {
      status: 200,
      payload: { response: { id: "user_other", object: "user" } },
      clientToken: "foreign-client",
    };
  });
  await NodeAssert.rejects(f.session.updateProfileName(identity, { firstName: "Other" }));
  NodeAssert.equal((await f.store.read()).clientToken, "active-client");
  NodeAssert.equal(await f.session.readRelayToken(), "example.relay.jwt");
});

NodeTest.test("clears an expired profile session", async () => {
  const f = fixture();
  await f.session.start("sign-in");
  const identity = await f.session.complete(callback);
  f.reply(({ path }) => (path === profilePath ? { status: 401 } : undefined));
  await NodeAssert.rejects(
    f.session.updateProfileName(identity, { firstName: "Expired" }),
    AccountSessionExpiredError,
  );
  NodeAssert.equal(await f.store.read(), undefined);
  await NodeAssert.rejects(f.session.readRelayToken(), AccountSessionExpiredError);
});

NodeTest.test("discards a profile result and credential arriving during sign-out", async () => {
  const f = fixture();
  await f.session.start("sign-in");
  const identity = await f.session.complete(callback);
  const requested = Promise.withResolvers();
  const reply = Promise.withResolvers();
  f.reply(({ path }) => {
    if (path !== profilePath) return;
    requested.resolve();
    return reply.promise;
  });
  const updated = NodeAssert.rejects(
    f.session.updateProfileName(identity, { firstName: "Late" }),
    AccountSessionExpiredError,
  );
  await requested.promise;
  const signedOut = f.session.signOut();
  reply.resolve({
    status: 200,
    payload: { response: { ...client().sessions[1].user, object: "user", first_name: "Late" } },
    clientToken: "late-profile-client",
  });
  await updated;
  await signedOut;
  NodeAssert.equal(await f.store.read(), undefined);
  NodeAssert.equal(f.calls.at(-1).clientToken, "active-client");
});

NodeTest.test(
  "lists the current Clerk session first and sorts the other active devices",
  async () => {
    const f = fixture();
    await f.session.start("sign-in");
    const identity = await f.session.complete(callback);
    f.reply(({ path }) => {
      if (path !== activeSessionsPath) return;
      return {
        status: 200,
        clientToken: "listed-client",
        sessionList: [
          { object: "session", id: "sess_third", status: "active", last_active_at: 1000 },
          { object: "session", id: "sess_ended", status: "ended", last_active_at: 4000 },
          { object: "session", id: "sess_first", status: "active", last_active_at: 2000 },
          {
            object: "session",
            id: "sess_second",
            status: "active",
            last_active_at: 3000,
            latest_activity: {
              object: "session_activity",
              device_type: "desktop",
              browser_name: "Firefox",
              ip_address: "192.0.2.1",
            },
          },
        ],
      };
    });

    NodeAssert.deepEqual(await f.session.listSessions(identity), [
      { id: "sess_first", deviceType: "", browserName: "", lastActiveAt: 2000 },
      { id: "sess_second", deviceType: "desktop", browserName: "Firefox", lastActiveAt: 3000 },
      { id: "sess_third", deviceType: "", browserName: "", lastActiveAt: 1000 },
    ]);
    NodeAssert.deepEqual(f.calls.at(-1), {
      method: "GET",
      path: activeSessionsPath,
      clientToken: "active-client",
    });
    NodeAssert.equal((await f.store.read()).clientToken, "listed-client");
  },
);

NodeTest.test(
  "rejects a Clerk session list without the current session without ending it",
  async () => {
    const f = fixture();
    await f.session.start("sign-in");
    const identity = await f.session.complete(callback);
    f.reply(({ path }) => {
      if (path !== activeSessionsPath) return;
      return { status: 200, sessionList: [] };
    });
    await NodeAssert.rejects(f.session.listSessions(identity), { name: "Error" });
    NodeAssert.equal(await f.session.readRelayToken(), "example.relay.jwt");
  },
);

NodeTest.test(
  "revokes an explicitly targeted other Clerk session and preserves the current session",
  async () => {
    const f = fixture();
    await f.session.start("sign-in");
    const identity = await f.session.complete(callback);
    const callCount = f.calls.length;
    await NodeAssert.rejects(f.session.revokeSession(identity, identity.sessionId));
    await NodeAssert.rejects(f.session.revokeSession(identity, "sess/invalid"));
    await NodeAssert.rejects(
      f.session.revokeSession({ ...identity, userId: "user_other" }, "sess_second"),
      AccountSessionExpiredError,
    );
    NodeAssert.equal(f.calls.length, callCount);
    f.reply(({ path }) => {
      if (path !== revokeOtherSessionPath) return;
      return {
        status: 200,
        clientToken: "revoked-client",
        payload: { response: { object: "session", id: "sess_second", status: "revoked" } },
      };
    });

    await f.session.revokeSession(identity, "sess_second");
    NodeAssert.deepEqual(f.calls.at(-1), {
      method: "POST",
      path: revokeOtherSessionPath,
      clientToken: "active-client",
      body: {},
    });
    NodeAssert.equal((await f.store.read()).sessionId, "sess_first");
    NodeAssert.equal(await f.session.readRelayToken(), "example.relay.jwt");
    NodeAssert.equal(f.calls.at(-1).clientToken, "revoked-client");
  },
);

NodeTest.test(
  "reports Clerk reverification and an already-gone target without signing out",
  async () => {
    const f = fixture();
    await f.session.start("sign-in");
    const identity = await f.session.complete(callback);
    f.reply(({ path }) => {
      if (path !== revokeOtherSessionPath) return;
      return { status: 401, payload: { errors: [{ code: "session_reverification_required" }] } };
    });
    const callCount = f.calls.length;
    await NodeAssert.rejects(
      f.session.revokeSession(identity, "sess_second"),
      (error) => !(error instanceof AccountSessionExpiredError) && /验证身份/.test(error.message),
    );
    NodeAssert.equal(f.calls.length, callCount + 1);
    NodeAssert.equal((await f.store.read()).sessionId, "sess_first");

    f.reply(({ path }) => {
      if (path !== revokeOtherSessionPath) return;
      return { status: 404, payload: { errors: [{ code: "session_not_found" }] } };
    });
    await NodeAssert.rejects(
      f.session.revokeSession(identity, "sess_second"),
      (error) => !(error instanceof AccountSessionExpiredError),
    );
    NodeAssert.equal(await f.session.readRelayToken(), "example.relay.jwt");
  },
);

NodeTest.test("discards a Clerk session list and rotated credential when signing out", async () => {
  const f = fixture();
  await f.session.start("sign-in");
  const identity = await f.session.complete(callback);
  const requested = Promise.withResolvers();
  const reply = Promise.withResolvers();
  f.reply(({ path }) => {
    if (path !== activeSessionsPath) return;
    requested.resolve();
    return reply.promise;
  });
  const listed = NodeAssert.rejects(f.session.listSessions(identity), AccountSessionExpiredError);
  await requested.promise;
  const signedOut = f.session.signOut();
  reply.resolve({
    status: 200,
    sessionList: [{ object: "session", id: "sess_first", status: "active" }],
    clientToken: "late-list-client",
  });
  await listed;
  await signedOut;
  NodeAssert.equal(await f.store.read(), undefined);
  NodeAssert.equal(f.calls.at(-1).clientToken, "active-client");
});

const signIns = "/client/sign_ins";
const signIn = (status, fields = {}) => ({
  object: "sign_in",
  id: "sia_fixture",
  status,
  ...fields,
});
const emailFactor = { strategy: "email_code", email_address_id: "idn_fixture" };
const firstFactors = [emailFactor, { strategy: "password" }];
const firstFactor = () => signIn("needs_first_factor", { supported_first_factors: firstFactors });
const completeSignIn = (id = "sia_fixture") => ({
  status: 200,
  clientToken: "verified-client",
  payload: {
    response: signIn("complete", { id, created_session_id: "sess_first" }),
    client: client(),
  },
});
const signInReply = (response, clientToken) => ({
  status: 200,
  payload: { response },
  clientToken,
});
const preparedFirst = `${signIns}/sia_fixture/prepare_first_factor`;
const attemptFirst = `${signIns}/sia_fixture/attempt_first_factor`;
const preparedSecond = `${signIns}/sia_fixture/prepare_second_factor`;
const attemptSecond = `${signIns}/sia_fixture/attempt_second_factor`;

NodeTest.test(
  "native email code uses Clerk's native client, retries a rejected code and restores the activated account",
  async () => {
    const f = fixture();
    f.reply(({ path, body }) => {
      if (path === signIns) return signInReply(firstFactor(), "sign-in-client");
      if (path === preparedFirst) return signInReply(firstFactor(), "prepare-client");
      if (path === attemptFirst) {
        if (body.code !== "123456") {
          return {
            status: 422,
            payload: { errors: [{ code: "form_code_incorrect" }] },
            clientToken: "retry-client",
          };
        }
        const reply = completeSignIn();
        return {
          ...reply,
          payload: { response: reply.payload.response, meta: { client: client() } },
        };
      }
    });
    await NodeAssert.rejects(f.session.email({ kind: "start", value: " " }));
    NodeAssert.equal(f.calls.length, 0);
    const step = await f.session.email({ kind: "start", value: " fixture@example.com " });
    NodeAssert.equal(step.kind, "emailCode");
    NodeAssert.equal(step.passwordAvailable, true);
    NodeAssert.deepEqual(f.calls.slice(0, 3), [
      { method: "GET", path: "/client", clientToken: "" },
      {
        method: "POST",
        path: signIns,
        clientToken: "anonymous-client",
        body: { identifier: "fixture@example.com" },
      },
      {
        method: "POST",
        path: preparedFirst,
        clientToken: "sign-in-client",
        body: { strategy: "email_code", email_address_id: "idn_fixture" },
      },
    ]);
    await NodeAssert.rejects(f.session.email({ kind: "verify", value: "000000" }), /验证码不正确/);
    NodeAssert.equal(await f.store.read(), undefined);
    const result = await f.session.email({ kind: "verify", value: "123456" });
    NodeAssert.equal(result.kind, "complete");
    NodeAssert.equal(result.identity.userId, "user_first");
    NodeAssert.deepEqual(f.calls.slice(3), [
      {
        method: "POST",
        path: attemptFirst,
        clientToken: "prepare-client",
        body: { strategy: "email_code", code: "000000" },
      },
      {
        method: "POST",
        path: attemptFirst,
        clientToken: "retry-client",
        body: { strategy: "email_code", code: "123456" },
      },
      {
        method: "POST",
        path: "/client/sessions/sess_first/touch",
        clientToken: "verified-client",
        body: { intent: "select_session" },
      },
    ]);
    const saved = await f.store.read();
    NodeAssert.deepEqual(saved, {
      issuer,
      sessionId: "sess_first",
      userId: "user_first",
      clientToken: "active-client",
    });
    NodeAssert.equal(await f.session.readRelayToken(), "example.relay.jwt");
    NodeAssert.equal((await fixture({ saved }).session.restore()).userId, "user_first");
  },
);

NodeTest.test(
  "password sign-in uses Clerk's replacement attempt and routes each supported second factor",
  async () => {
    const secondStrategies = [
      ["needs_client_trust", [emailFactor, { strategy: "totp" }], "mfaEmail", "email_code"],
      ["needs_second_factor", [{ strategy: "totp" }, { strategy: "backup_code" }], "totp", "totp"],
      ["needs_second_factor", [{ strategy: "backup_code" }], "backupCode", "backup_code"],
    ];
    for (const [status, supportedSecondFactors, kind, strategy] of secondStrategies) {
      const f = fixture();
      const challenge = signIn(status, {
        id: "sia_password",
        supported_second_factors: supportedSecondFactors,
      });
      f.reply(({ path, body }) => {
        if (path === signIns)
          return signInReply(body.password ? challenge : firstFactor(), "sign-in-client");
        if (path === preparedFirst) return signInReply(firstFactor());
        if (path === preparedSecond.replace("sia_fixture", "sia_password"))
          return signInReply(challenge, "mfa-client");
        if (path === attemptSecond.replace("sia_fixture", "sia_password"))
          return completeSignIn("sia_password");
      });
      NodeAssert.equal(
        (await f.session.email({ kind: "start", value: "fixture@example.com" })).kind,
        "emailCode",
      );
      const password = await f.session.email({ kind: "password" });
      NodeAssert.equal(password.kind, "password");
      NodeAssert.equal(password.emailCodeAvailable, true);
      NodeAssert.equal(
        (await f.session.email({ kind: "verify", value: " fixture-password " })).kind,
        kind,
      );
      NodeAssert.deepEqual(f.calls[3], {
        method: "POST",
        path: signIns,
        clientToken: "sign-in-client",
        body: { identifier: "fixture@example.com", password: " fixture-password " },
      });
      if (kind === "mfaEmail") {
        NodeAssert.deepEqual(f.calls[4], {
          method: "POST",
          path: preparedSecond.replace("sia_fixture", "sia_password"),
          clientToken: "sign-in-client",
          body: { strategy: "email_code", email_address_id: "idn_fixture" },
        });
        NodeAssert.equal((await f.session.email({ kind: "resend" })).kind, "mfaEmail");
      }
      NodeAssert.equal(await f.store.read(), undefined);
      const code = kind === "backupCode" ? "fixture-backup" : "111111";
      NodeAssert.equal((await f.session.email({ kind: "verify", value: code })).kind, "complete");
      NodeAssert.deepEqual(f.calls.at(-2), {
        method: "POST",
        path: attemptSecond.replace("sia_fixture", "sia_password"),
        clientToken: kind === "mfaEmail" ? "mfa-client" : "sign-in-client",
        body: { strategy, code },
      });
    }
  },
);

NodeTest.test(
  "unsupported factors and Clerk challenges leave the browser path available without persisting credentials",
  async () => {
    for (const reply of [
      signInReply(
        signIn("needs_first_factor", { supported_first_factors: [{ strategy: "passkey" }] }),
      ),
      signInReply(signIn("needs_protect_check")),
      { status: 422, payload: { errors: [{ code: "captcha_missing_token" }] } },
      { status: 401, payload: { errors: [{ code: "requires_captcha" }] } },
    ]) {
      const f = fixture();
      f.reply(({ path }) => (path === signIns ? reply : undefined));
      NodeAssert.equal(
        (await f.session.email({ kind: "start", value: "fixture@example.com" })).kind,
        "hosted",
      );
      NodeAssert.equal(await f.store.read(), undefined);
      NodeAssert.equal(await f.session.start("sign-in"), browserUrl);
      NodeAssert.equal((await f.session.complete(callback)).userId, "user_first");
    }
  },
);

NodeTest.test(
  "a failed MFA code send keeps its challenge so retry does not repeat the password",
  async () => {
    const f = fixture();
    let reachable = false;
    const passwordOnly = signIn("needs_first_factor", {
      supported_first_factors: [{ strategy: "password" }],
    });
    const second = signIn("needs_client_trust", { supported_second_factors: [emailFactor] });
    f.reply(({ path, body }) => {
      if (path === signIns) return signInReply(body.password ? second : passwordOnly);
      if (path === preparedSecond)
        return reachable ? signInReply(second) : Promise.reject(new Error("Offline fixture"));
      if (path === attemptSecond) return completeSignIn();
    });
    NodeAssert.equal(
      (await f.session.email({ kind: "start", value: "fixture@example.com" })).kind,
      "password",
    );
    const step = await f.session.email({ kind: "verify", value: "fixture-password" });
    NodeAssert.equal(step.kind, "mfaEmail");
    NodeAssert.match(step.error, /Offline fixture/);
    reachable = true;
    NodeAssert.equal((await f.session.email({ kind: "resend" })).error, undefined);
    NodeAssert.equal((await f.session.email({ kind: "verify", value: "123456" })).kind, "complete");
    NodeAssert.equal(f.calls.filter(({ body }) => body?.password).length, 1);
  },
);

NodeTest.test(
  "cancelled native activation and late browser callbacks cannot commit an account",
  async () => {
    const previous = fixture();
    await previous.session.start("sign-in");
    const f = fixture({ pending: await previous.store.readAttempt() });
    const requested = Promise.withResolvers();
    const activation = Promise.withResolvers();
    f.reply(({ path }) => {
      if (path === signIns || path === preparedFirst) return signInReply(firstFactor());
      if (path === attemptFirst) return completeSignIn();
      if (path === "/client/sessions/sess_first/touch") {
        requested.resolve();
        return activation.promise;
      }
    });
    await f.session.email({ kind: "start", value: "fixture@example.com" });
    await NodeAssert.rejects(f.session.complete(callback));
    await NodeAssert.rejects(f.session.start("sign-in"));
    NodeAssert.equal(f.redeemCount(), 0);
    const checking = NodeAssert.rejects(f.session.email({ kind: "verify", value: "123456" }));
    await requested.promise;
    f.session.cancel();
    activation.resolve({
      status: 200,
      payload: { response: client().sessions[1] },
      clientToken: "ignored-client",
    });
    await checking;
    NodeAssert.equal(await f.store.read(), undefined);
    await NodeAssert.rejects(f.session.readRelayToken());
    NodeAssert.equal(await f.session.start("sign-in"), browserUrl);
  },
);
