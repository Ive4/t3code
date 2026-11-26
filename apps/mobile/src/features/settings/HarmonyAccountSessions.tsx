import { useAuth, useClerk, type useUser } from "@clerk/expo";
import { useGT, useLocale } from "gt-react-native";
import { useEffect, useRef, useState } from "react";
import { View } from "react-native";

import { AppActivityIndicator } from "../../components/ui/AppActivityIndicator";
import { AppText } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";
import * as Dialog from "../../components/ui/Dialog";

type AccountUser = Pick<NonNullable<ReturnType<typeof useUser>["user"]>, "id" | "getSessions">;
type AccountSession = Awaited<ReturnType<AccountUser["getSessions"]>>[number];
type SessionList =
  | { readonly status: "loading" | "error" }
  | { readonly status: "ready"; readonly sessions: ReadonlyArray<AccountSession> };

async function readActiveSessions(user: AccountUser, sessionId: string): Promise<SessionList> {
  const sessions = (await user.getSessions()).filter((session) => session.status === "active");
  const current = sessions.find((session) => session.id === sessionId);
  // Clerk can return an empty array after a failed request, even while signed in.
  if (!current) return { status: "error" };
  const others = sessions
    .filter((session) => session.id !== sessionId)
    .sort(
      (left, right) => (right.lastActiveAt?.getTime() ?? 0) - (left.lastActiveAt?.getTime() ?? 0),
    );
  return { status: "ready", sessions: [current, ...others] };
}

export function HarmonyAccountSessions({ user }: { readonly user: AccountUser }) {
  const { sessionId } = useAuth();
  return sessionId ? (
    <ActiveSessions key={`${user.id}:${sessionId}`} user={user} sessionId={sessionId} />
  ) : null;
}

function ActiveSessions({
  user,
  sessionId,
}: {
  readonly user: AccountUser;
  readonly sessionId: string;
}) {
  const clerk = useClerk();
  const gt = useGT();
  const locale = useLocale();
  const [list, setList] = useState<SessionList>({ status: "loading" });
  const [revokingId, setRevokingId] = useState<string | null>(null);
  const [revokeFailed, setRevokeFailed] = useState(false);
  const pendingRetry = useRef(false);
  const pendingRevoke = useRef(false);
  const userId = user.id;
  const isCurrentSession = () => clerk.session?.id === sessionId && clerk.user?.id === userId;

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- loads the signed-in account's sessions from Clerk
  useEffect(() => {
    if (pendingRetry.current) return;
    let cancelled = false;
    void readActiveSessions(user, sessionId).then(
      (next) => {
        if (!cancelled) setList(next);
      },
      () => {
        if (!cancelled) setList({ status: "error" });
      },
    );
    return () => {
      cancelled = true;
    };
  }, [sessionId, user]);

  async function retry() {
    const session = clerk.session;
    if (pendingRetry.current || !session || !isCurrentSession()) return;
    pendingRetry.current = true;
    setList({ status: "loading" });
    try {
      // Clerk caches getSessions() results on the user, including empty results after a failure.
      const refreshed = await session.reload();
      if (!isCurrentSession()) return;
      if (refreshed.id !== sessionId || refreshed.user.id !== userId) {
        setList({ status: "error" });
        return;
      }
      const next = await readActiveSessions(refreshed.user, sessionId);
      if (isCurrentSession()) setList(next);
    } catch {
      if (isCurrentSession()) setList({ status: "error" });
    } finally {
      pendingRetry.current = false;
    }
  }

  async function revoke(session: AccountSession) {
    if (
      pendingRevoke.current ||
      session.id === sessionId ||
      session.status !== "active" ||
      !isCurrentSession()
    ) {
      return;
    }
    pendingRevoke.current = true;
    setRevokingId(session.id);
    setRevokeFailed(false);
    try {
      await session.revoke();
      setList((current) =>
        current.status === "ready"
          ? {
              status: "ready",
              sessions: current.sessions.filter((entry) => entry.id !== session.id),
            }
          : current,
      );
    } catch {
      setRevokeFailed(true);
    } finally {
      pendingRevoke.current = false;
      setRevokingId(null);
    }
  }

  const dateFormat = new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeStyle: "short" });
  return (
    <View className="gap-3 rounded-[24px] bg-grouped-card p-4">
      <AppText accessibilityRole="header" textRole="body" className="font-t3-semibold">
        {gt("Active sessions")}
      </AppText>
      {list.status === "loading" ? (
        <AppActivityIndicator accessibilityLabel={gt("Loading active sessions")} />
      ) : list.status === "error" ? (
        <>
          <AppText accessibilityRole="alert" className="text-danger-foreground">
            {gt("Could not load active sessions.")}
          </AppText>
          <Button
            label={gt("Retry")}
            tone="secondary"
            size="compact"
            onPress={() => void retry()}
          />
        </>
      ) : null}
      {list.status === "ready"
        ? list.sessions.map((session) => {
            const current = session.id === sessionId;
            const activity = session.latestActivity;
            const device = [activity.deviceType, activity.browserName].filter(Boolean).join(" · ");
            const title = device || gt("Unknown device");
            const lastActiveAt = session.lastActiveAt;
            return (
              <View
                key={session.id}
                className="flex-row flex-wrap items-center gap-3 border-t border-border-subtle pt-3"
              >
                <View className="min-w-28 flex-1 gap-1">
                  <AppText>{title}</AppText>
                  {current ? (
                    <AppText textRole="footnote" className="text-foreground-muted">
                      {gt("Current session")}
                    </AppText>
                  ) : null}
                  {lastActiveAt && Number.isFinite(lastActiveAt.getTime()) ? (
                    <AppText textRole="footnote" className="text-foreground-muted">
                      {gt("Last active {date}", { date: dateFormat.format(lastActiveAt) })}
                    </AppText>
                  ) : null}
                </View>
                {current ? null : (
                  <Button
                    label={gt("Sign out")}
                    accessibilityLabel={gt("Sign out of {device}", { device: title })}
                    size="compact"
                    disabled={revokingId !== null}
                    loading={revokingId === session.id}
                    onPress={() =>
                      Dialog.confirm({
                        title: gt("Sign out of this session?"),
                        message: gt("This will sign out the session on {device}.", {
                          device: title,
                        }),
                        confirmText: gt("Sign out"),
                        destructive: true,
                        onConfirm: () => void revoke(session),
                      })
                    }
                  />
                )}
              </View>
            );
          })
        : null}
      {revokeFailed ? (
        <AppText accessibilityRole="alert" className="text-danger-foreground">
          {gt("Could not sign out. Try again.")}
        </AppText>
      ) : null}
    </View>
  );
}
