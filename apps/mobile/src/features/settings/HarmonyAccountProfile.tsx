import { useAuth, useUser } from "@clerk/expo";
import { useFocusEffect } from "@react-navigation/native";
import { useGT } from "gt-react-native";
import { useCallback, useRef, useState, type ReactNode } from "react";
import { BackHandler, Image, Keyboard, View } from "react-native";
import { KeyboardAvoidingView } from "react-native-keyboard-controller";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { AppActivityIndicator } from "../../components/ui/AppActivityIndicator";
import { AppBar } from "../../components/ui/AppBar";
import { SymbolView } from "../../components/ui/AppSymbol";
import { AppText, AppTextInput } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";
import { ListRow } from "../../components/ui/ListRow";
import { ScreenScrollView } from "../../components/ui/ScreenScrollView";
import { T3ConnectProfilePage } from "../cloud/T3ConnectProfilePage";
import { SettingsSection } from "./components/SettingsSection";
import { HarmonyAccountAvatarEditor } from "./HarmonyAccountAvatarEditor";
import { HarmonyAccountDelete } from "./HarmonyAccountDelete";
import { HarmonyAccountEmailAddresses } from "./HarmonyAccountEmailAddresses";
import {
  HarmonyAccountLinkedAccounts,
  HarmonyAccountPasskeys,
} from "./HarmonyAccountLinkedAccounts";
import { HarmonyAccountMfa } from "./HarmonyAccountMfa";
import { HarmonyAccountPassword } from "./HarmonyAccountPassword";
import { HarmonyAccountSessions } from "./HarmonyAccountSessions";

type AccountPage = "root" | "account" | "security" | "connect";
type AccountName = { readonly firstName: string; readonly lastName: string };
type AccountUser = NonNullable<ReturnType<typeof useUser>["user"]>;
type AccountNavigation = { readonly onBack: () => void; readonly onSignedOut: () => void };

export function HarmonyAccountProfile(props: AccountNavigation) {
  const { user } = useUser();
  if (!user) {
    return (
      <View className="flex-1 items-center justify-center">
        <AppActivityIndicator />
      </View>
    );
  }
  return <AccountPages key={user.id} user={user} {...props} />;
}

function AccountPages({
  user,
  onBack,
  onSignedOut,
}: AccountNavigation & { readonly user: AccountUser }) {
  const gt = useGT();
  const [page, setPage] = useState<AccountPage>("root");
  const [signingOut, setSigningOut] = useState(false);
  const [signOutFailed, setSignOutFailed] = useState(false);
  const signOutPending = useRef(false);
  const { signOut } = useAuth();

  const back = useCallback(() => {
    Keyboard.dismiss();
    if (page === "root") onBack();
    else setPage("root");
  }, [onBack, page]);

  useFocusEffect(
    useCallback(() => {
      if (page === "root") return;
      const listener = BackHandler.addEventListener("hardwareBackPress", () => {
        back();
        return true;
      });
      return () => listener.remove();
    }, [back, page]),
  );

  async function signOutOfAccount() {
    if (signOutPending.current) return;
    signOutPending.current = true;
    setSigningOut(true);
    setSignOutFailed(false);
    try {
      await signOut();
      onSignedOut();
    } catch {
      setSignOutFailed(true);
    } finally {
      signOutPending.current = false;
      setSigningOut(false);
    }
  }

  const titles = {
    root: gt("T3 Account"),
    account: gt("Manage account"),
    security: gt("Security"),
    connect: "T3 Connect",
  };
  return (
    <View className="flex-1 bg-sheet">
      <AppBar title={titles[page]} onBack={back} />
      {page === "account" ? (
        <AccountDetails user={user} />
      ) : page === "security" ? (
        <AccountScroll>
          <HarmonyAccountPassword />
          <HarmonyAccountPasskeys />
          <HarmonyAccountMfa />
          <HarmonyAccountSessions user={user} />
          <HarmonyAccountDelete onDeleted={onSignedOut} />
        </AccountScroll>
      ) : page === "connect" ? (
        <T3ConnectProfilePage />
      ) : (
        <AccountScroll>
          <View className="items-center gap-2 px-4 py-3">
            <View className="size-20 items-center justify-center overflow-hidden rounded-full bg-subtle">
              <SymbolView
                name="person.crop.circle"
                size={36}
                tintColorClassName="accent-foreground-muted"
              />
              {user.imageUrl ? (
                <Image
                  accessible={false}
                  source={{ uri: user.imageUrl }}
                  className="absolute size-20"
                />
              ) : null}
            </View>
            <AppText textRole="headline" className="text-center font-t3-semibold">
              {[user.firstName, user.lastName].filter(Boolean).join(" ") ||
                user.username ||
                gt("Signed in")}
            </AppText>
            {user.primaryEmailAddress ? (
              <AppText textRole="footnote" className="text-center text-foreground-muted">
                {user.primaryEmailAddress.emailAddress}
              </AppText>
            ) : null}
          </View>
          <SettingsSection>
            <ListRow
              icon="person.crop.circle"
              label={titles.account}
              disabled={signingOut}
              onPress={() => setPage("account")}
            />
            <ListRow
              icon={{ ios: "lock.shield", android: "lock" }}
              label={titles.security}
              disabled={signingOut}
              onPress={() => setPage("security")}
            />
            <ListRow
              icon="globe"
              label={titles.connect}
              disabled={signingOut}
              onPress={() => setPage("connect")}
            />
          </SettingsSection>
          <View className="gap-2">
            {signOutFailed ? (
              <AppText accessibilityRole="alert" className="text-danger-foreground">
                {gt("Could not sign out. Try again.")}
              </AppText>
            ) : null}
            <Button
              label={gt("Sign out")}
              tone="danger"
              fullWidth
              disabled={signingOut}
              loading={signingOut}
              onPress={() => void signOutOfAccount()}
            />
          </View>
        </AccountScroll>
      )}
    </View>
  );
}

function AccountScroll({ children }: { readonly children: ReactNode }) {
  const { bottom } = useSafeAreaInsets();
  return (
    <KeyboardAvoidingView automaticOffset behavior="padding" className="flex-1">
      <ScreenScrollView
        className="flex-1"
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
        contentContainerStyle={{ paddingBottom: Math.max(bottom, 16) + 16 }}
      >
        <View className="w-full max-w-[540px] gap-5 self-center px-5 pt-3">{children}</View>
      </ScreenScrollView>
    </KeyboardAvoidingView>
  );
}

function AccountDetails({ user }: { readonly user: AccountUser }) {
  const gt = useGT();
  const [draft, setDraft] = useState<{
    readonly initial: AccountName;
    readonly values: AccountName;
  } | null>(null);
  const [pending, setPending] = useState(false);
  const [failed, setFailed] = useState(false);
  const actionPending = useRef(false);

  const currentName = { firstName: user.firstName ?? "", lastName: user.lastName ?? "" };
  const canEditName = typeof user.update === "function";
  const nextFirstName = draft?.values.firstName.trim();
  const nextLastName = draft?.values.lastName.trim();
  const updates = {
    ...(nextFirstName !== undefined && nextFirstName !== draft?.initial.firstName.trim()
      ? { firstName: nextFirstName || null }
      : {}),
    ...(nextLastName !== undefined && nextLastName !== draft?.initial.lastName.trim()
      ? { lastName: nextLastName || null }
      : {}),
  };
  const canSave = Object.keys(updates).length > 0;
  const nameFields = [
    { key: "firstName", label: gt("First name"), autoComplete: "given-name" },
    { key: "lastName", label: gt("Last name"), autoComplete: "family-name" },
  ] as const;

  async function saveName() {
    if (actionPending.current) return;
    actionPending.current = true;
    setPending(true);
    setFailed(false);
    try {
      await user.update(updates);
      setDraft(null);
    } catch {
      setFailed(true);
    } finally {
      actionPending.current = false;
      setPending(false);
    }
  }

  return (
    <AccountScroll>
      <View className="gap-4 rounded-[24px] bg-grouped-card p-4">
        <HarmonyAccountAvatarEditor user={user} />
        {draft ? (
          <View className="gap-3">
            {nameFields.map(({ key, label, autoComplete }) => (
              <View key={key} className="gap-1.5">
                <AppText textRole="footnote">{label}</AppText>
                <AppTextInput
                  accessibilityLabel={label}
                  autoComplete={autoComplete}
                  autoCapitalize="words"
                  autoCorrect={false}
                  editable={!pending}
                  value={draft.values[key]}
                  onChangeText={(value) =>
                    setDraft(
                      (current) =>
                        current && { ...current, values: { ...current.values, [key]: value } },
                    )
                  }
                />
              </View>
            ))}
            {failed ? (
              <AppText accessibilityRole="alert" className="text-danger-foreground">
                {gt("Could not update your profile. Try again.")}
              </AppText>
            ) : null}
            <View className="flex-row flex-wrap gap-2">
              <Button
                label={gt("Save changes")}
                tone="primary"
                disabled={!canSave || Boolean(pending)}
                loading={pending}
                onPress={() => {
                  Keyboard.dismiss();
                  void saveName();
                }}
              />
              <Button
                label={gt("Cancel")}
                tone="text"
                disabled={Boolean(pending)}
                onPress={() => {
                  Keyboard.dismiss();
                  setFailed(false);
                  setDraft(null);
                }}
              />
            </View>
          </View>
        ) : canEditName ? (
          <Button
            label={gt("Edit profile")}
            disabled={Boolean(pending)}
            onPress={() => {
              setFailed(false);
              setDraft({ initial: currentName, values: currentName });
            }}
          />
        ) : null}
      </View>
      <HarmonyAccountEmailAddresses />
      <HarmonyAccountLinkedAccounts />
    </AccountScroll>
  );
}
