import { useClerk, useSession, useUser } from "@clerk/expo";
import type { UserResource } from "@clerk/expo/types";
import { useGT } from "gt-react-native";
import { useEffectEvent, useLayoutEffect, useRef, useState } from "react";
import { AppState, Linking, View } from "react-native";

import { AppText, AppTextInput } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";
import * as Dialog from "../../components/ui/Dialog";
import { ListRowLayout } from "../../components/ui/ListRowLayout";
import { harmonyAccountRedirect, openAuthSessionAsync } from "../cloud/harmonyHostedAuth";
import { SettingsSection } from "./components/SettingsSection";
import {
  isHarmonyReverificationCancelled,
  useHarmonyAccountReverification,
} from "./HarmonyAccountReverification";

const providers = [
  { strategy: "oauth_google", provider: "google", name: "Google" },
  { strategy: "oauth_github", provider: "github", name: "GitHub" },
  { strategy: "oauth_apple", provider: "apple", name: "Apple" },
  { strategy: "oauth_microsoft", provider: "microsoft", name: "Microsoft" },
] as const;

type Section = "linked" | "passkeys";
type Connect =
  | { readonly kind: "connect"; readonly strategy: (typeof providers)[number]["strategy"] }
  | { readonly kind: "reauthorize"; readonly id: string };
type Mutation =
  | Connect
  | { readonly kind: "removeExternal" | "removePasskey"; readonly id: string }
  | { readonly kind: "renamePasskey"; readonly id: string; readonly name: string };
type Operation = "connect" | "update" | "browser";

function isVerified(resource: {
  readonly verification: { readonly status: string | null } | null;
}) {
  return resource.verification?.status === "verified";
}

function hasOtherSignInMethod(user: UserResource, removedId: string) {
  return (
    user.passwordEnabled ||
    user.emailAddresses.some(isVerified) ||
    user.phoneNumbers.some(isVerified) ||
    user.externalAccounts.some((account) => account.id !== removedId && isVerified(account)) ||
    user.passkeys.some((passkey) => passkey.id !== removedId && isVerified(passkey))
  );
}

function secureBrowserUrl(value: string) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password ? url.href : null;
  } catch {
    return null;
  }
}

function passkeyBrowserUrl(clerk: ReturnType<typeof useClerk>) {
  try {
    return secureBrowserUrl(clerk.buildUserProfileUrl());
  } catch {
    return null;
  }
}

export function HarmonyAccountLinkedAccounts() {
  return <AccountMethods section="linked" />;
}

export function HarmonyAccountPasskeys() {
  return <AccountMethods section="passkeys" />;
}

function AccountMethods({ section }: { readonly section: Section }) {
  const { user } = useUser();
  const { session } = useSession();
  return user && session ? (
    <AccountMethodSection user={user} sessionId={session.id} section={section} key={session.id} />
  ) : null;
}

function AccountMethodSection({
  user,
  sessionId,
  section,
}: {
  readonly user: UserResource;
  readonly sessionId: string;
  readonly section: Section;
}) {
  const gt = useGT();
  const clerk = useClerk();
  const [pending, setPending] = useState<Operation | null>(null);
  const [failed, setFailed] = useState<Operation | null>(null);
  const [waitingForOAuth, setWaitingForOAuth] = useState(false);
  const [rename, setRename] = useState<{ id: string; name: string } | null>(null);
  const active = useRef(false);
  const operation = useRef<AbortController | null>(null);
  const refreshAfterBrowser = useRef(false);

  function activeUser() {
    return active.current && clerk.user?.id === user.id && clerk.session?.id === sessionId
      ? clerk.user
      : null;
  }

  const { run, prompt } = useHarmonyAccountReverification(async (mutation: Mutation) => {
    const account = activeUser();
    if (!account) throw new Error("The account session has changed.");
    if (mutation.kind === "connect") {
      return account.createExternalAccount({
        strategy: mutation.strategy,
        redirectUrl: harmonyAccountRedirect,
      });
    }
    if (mutation.kind === "reauthorize" || mutation.kind === "removeExternal") {
      const external = account.externalAccounts.find((entry) => entry.id === mutation.id);
      if (!external) throw new Error("The connected account no longer exists.");
      if (mutation.kind === "reauthorize") {
        return external.reauthorize({ redirectUrl: harmonyAccountRedirect });
      }
      if (isVerified(external) && !hasOtherSignInMethod(account, external.id)) {
        throw new Error("The last sign-in method cannot be removed.");
      }
      await external.destroy();
      return;
    }
    const passkey = account.passkeys.find((entry) => entry.id === mutation.id);
    if (!passkey) throw new Error("The passkey no longer exists.");
    if (mutation.kind === "renamePasskey") {
      await passkey.update({ name: mutation.name });
    } else {
      if (!hasOtherSignInMethod(account, passkey.id)) {
        throw new Error("The last sign-in method cannot be removed.");
      }
      await passkey.delete();
    }
  });

  async function perform(kind: Operation, action: (signal: AbortSignal) => Promise<void>) {
    if (operation.current || !activeUser()) return;
    const controller = new AbortController();
    operation.current = controller;
    setPending(kind);
    setFailed(null);
    try {
      await action(controller.signal);
    } catch (error) {
      if (!controller.signal.aborted && activeUser() && !isHarmonyReverificationCancelled(error)) {
        setFailed(kind);
      }
    } finally {
      operation.current = null;
      if (activeUser()) {
        setPending(null);
        setWaitingForOAuth(false);
      }
    }
  }

  const refreshOnReturn = useEffectEvent(() => {
    if (!refreshAfterBrowser.current) return;
    refreshAfterBrowser.current = false;
    void activeUser()
      ?.reload()
      .catch(() => {
        if (activeUser()) setFailed("update");
      });
  });
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- cancels OAuth on close and refreshes passkeys after returning from the browser
  useLayoutEffect(() => {
    active.current = true;
    const subscription =
      section === "passkeys"
        ? AppState.addEventListener("change", (state) => {
            if (state === "active") refreshOnReturn();
          })
        : undefined;
    return () => {
      active.current = false;
      operation.current?.abort();
      subscription?.remove();
    };
  }, [operation, section]);

  function connect(mutation: Connect) {
    void perform("connect", async (signal) => {
      const external = await run(mutation);
      if (signal.aborted || !activeUser()) return;
      if (!external) throw new Error("Clerk did not return the connected account.");
      let completed = isVerified(external);
      let current: UserResource | undefined;
      try {
        if (!completed) {
          const url = secureBrowserUrl(
            external.verification?.externalVerificationRedirectURL?.href ?? "",
          );
          if (!url) throw new Error("Clerk did not return an OAuth authorization URL.");
          setWaitingForOAuth(true);
          const result = await openAuthSessionAsync(url, harmonyAccountRedirect, { signal });
          completed = result.type === "success";
        }
      } finally {
        // A canceled attempt can still leave a connection that Clerk lets the user resume.
        current = await activeUser()?.reload();
      }
      // A browser callback alone is no proof that the chosen identifier was verified.
      if (
        completed &&
        !current?.externalAccounts.some((entry) => entry.id === external.id && isVerified(entry))
      ) {
        throw new Error("The external account has not been verified.");
      }
    });
  }

  function remove(kind: "removeExternal" | "removePasskey", id: string, name: string) {
    Dialog.confirm({
      title: gt("Remove {name}?", { name }),
      message: gt("This will remove this sign-in method from your T3 Account."),
      confirmText: gt("Remove"),
      destructive: true,
      onConfirm: () =>
        void perform("update", async () => {
          await run({ kind, id });
          await activeUser()?.reload();
        }),
    });
  }

  const title = section === "linked" ? gt("Connected accounts") : gt("Passkeys");
  if (prompt) return <SettingsSection title={title}>{prompt}</SettingsSection>;

  const disabled = pending !== null || rename !== null;
  const portal = section === "passkeys" ? passkeyBrowserUrl(clerk) : null;
  const requiresBackup =
    section === "linked"
      ? user.externalAccounts.some(
          (entry) => isVerified(entry) && !hasOtherSignInMethod(user, entry.id),
        )
      : user.passkeys.some((entry) => !hasOtherSignInMethod(user, entry.id));
  return (
    <SettingsSection
      title={title}
      footer={requiresBackup ? gt("Keep at least one sign-in method.") : undefined}
    >
      {failed ? (
        <AppText accessibilityRole="alert" className="px-4 py-2 text-danger-foreground">
          {failed === "connect"
            ? gt("Could not connect this account. Try again.")
            : gt("The action could not be completed. Try again.")}
        </AppText>
      ) : null}
      {section === "linked" ? (
        <>
          {user.externalAccounts.map((account) => {
            const label = account.providerTitle();
            const verified = isVerified(account);
            return (
              <View key={account.id}>
                <ListRowLayout
                  label={label}
                  description={account.accountIdentifier() || undefined}
                  detail={verified ? gt("Connected") : gt("Unverified")}
                />
                <View className="flex-row flex-wrap gap-2 px-4 pb-3">
                  {!verified ? (
                    <Button
                      label={gt("Continue connecting")}
                      tone="text"
                      disabled={disabled}
                      onPress={() => connect({ kind: "reauthorize", id: account.id })}
                    />
                  ) : null}
                  <Button
                    label={gt("Remove")}
                    accessibilityLabel={gt("Remove {name}", { name: label })}
                    tone="text"
                    disabled={disabled || (verified && !hasOtherSignInMethod(user, account.id))}
                    onPress={() => remove("removeExternal", account.id, label)}
                  />
                </View>
              </View>
            );
          })}
          <View className="flex-row flex-wrap gap-2 px-4 py-3">
            {providers
              .filter(
                ({ provider }) =>
                  !user.externalAccounts.some((entry) => entry.providerSlug() === provider),
              )
              .map(({ strategy, name }) => (
                <Button
                  key={strategy}
                  label={gt("Connect {provider}", { provider: name })}
                  size="compact"
                  disabled={disabled}
                  onPress={() => connect({ kind: "connect", strategy })}
                />
              ))}
            {waitingForOAuth ? (
              <Button label={gt("Cancel")} tone="text" onPress={() => operation.current?.abort()} />
            ) : null}
          </View>
        </>
      ) : (
        <>
          {user.passkeys.length === 0 ? <ListRowLayout label={gt("No passkeys")} /> : null}
          {user.passkeys.map((passkey) => {
            const name = passkey.name ?? gt("Passkey");
            return (
              <View key={passkey.id}>
                <ListRowLayout label={name} />
                {rename?.id === passkey.id ? (
                  <View className="gap-2 px-4 pb-3">
                    <AppTextInput
                      accessibilityLabel={gt("Passkey name")}
                      value={rename.name}
                      editable={pending === null}
                      autoFocus
                      onChangeText={(value) => setRename({ id: passkey.id, name: value })}
                    />
                    <View className="flex-row flex-wrap gap-2">
                      <Button
                        label={gt("Save changes")}
                        tone="primary"
                        loading={pending === "update"}
                        disabled={!rename.name.trim() || rename.name.trim() === passkey.name}
                        onPress={() =>
                          void perform("update", async () => {
                            await run({
                              kind: "renamePasskey",
                              id: passkey.id,
                              name: rename.name.trim(),
                            });
                            await activeUser()?.reload();
                            if (activeUser()) setRename(null);
                          })
                        }
                      />
                      <Button
                        label={gt("Cancel")}
                        tone="text"
                        disabled={pending !== null}
                        onPress={() => setRename(null)}
                      />
                    </View>
                  </View>
                ) : (
                  <View className="flex-row flex-wrap gap-2 px-4 pb-3">
                    <Button
                      label={gt("Rename")}
                      accessibilityLabel={gt("Rename {name}", { name })}
                      tone="text"
                      disabled={disabled}
                      onPress={() => setRename({ id: passkey.id, name: passkey.name ?? "" })}
                    />
                    <Button
                      label={gt("Remove")}
                      accessibilityLabel={gt("Remove {name}", { name })}
                      tone="text"
                      disabled={disabled || !hasOtherSignInMethod(user, passkey.id)}
                      onPress={() => remove("removePasskey", passkey.id, name)}
                    />
                  </View>
                )}
              </View>
            );
          })}
          {portal ? (
            <View className="gap-2 px-4 py-3">
              <Button
                label={gt("Manage passkeys in browser")}
                disabled={disabled}
                onPress={() =>
                  void perform("browser", async () => {
                    refreshAfterBrowser.current = true;
                    try {
                      await Linking.openURL(portal);
                    } catch (error) {
                      refreshAfterBrowser.current = false;
                      throw error;
                    }
                  })
                }
              />
              <AppText textRole="footnote" className="text-foreground-muted">
                {gt("You may need to sign in again in your browser.")}
              </AppText>
            </View>
          ) : null}
        </>
      )}
    </SettingsSection>
  );
}
