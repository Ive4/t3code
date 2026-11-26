import { act, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";

const clerk = vi.hoisted(() => ({
  update: vi.fn(),
  signOut: vi.fn(),
  lastName: "",
  userId: "user",
  deleteSelfEnabled: false,
  delete: vi.fn(),
  reload: vi.fn(),
  setProfileImage: vi.fn(),
}));
const photo = vi.hoisted(() => ({
  pick: vi.fn(),
  resize: vi.fn(),
  deleteTemporary: vi.fn(),
}));

vi.mock("@clerk/expo", () => ({
  useAuth: () => ({ signOut: clerk.signOut }),
  useClerk: () => ({ session: { id: "current" }, user: { id: clerk.userId } }),
  useUser: () => ({
    isLoaded: true,
    user: {
      id: clerk.userId,
      firstName: "Ada",
      lastName: clerk.lastName,
      deleteSelfEnabled: clerk.deleteSelfEnabled,
      delete: clerk.delete,
      reload: clerk.reload,
      setProfileImage: clerk.setProfileImage,
      primaryEmailAddress: { emailAddress: "ada@example.com" },
      update: clerk.update,
    },
  }),
}));
vi.mock("react-native", () => ({
  View: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
  Image: () => null,
  Keyboard: { dismiss: () => {} },
}));
vi.mock("react-native-safe-area-context", () => ({ useSafeAreaInsets: () => ({ bottom: 0 }) }));
vi.mock("@react-navigation/native", () => ({ useFocusEffect() {} }));
vi.mock("react-native-keyboard-controller", () => ({
  KeyboardAvoidingView: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
}));
vi.mock("expo-image-picker", () => ({ launchImageLibraryAsync: photo.pick }));
vi.mock("expo-image-manipulator", () => ({
  SaveFormat: { JPEG: "jpeg" },
  ImageManipulator: {
    manipulate: () => ({
      resize: photo.resize.mockImplementation(() => ({
        renderAsync: async () => ({
          saveAsync: async () => ({ uri: "file:///cache/avatar.jpeg", base64: "AA==" }),
        }),
      })),
    }),
  },
}));
vi.mock("expo-file-system", () => ({
  File: class {
    exists = true;
    delete = photo.deleteTemporary;
  },
}));
vi.mock("../../components/ui/AppActivityIndicator", () => ({ AppActivityIndicator: () => null }));
vi.mock("../../components/ui/AppBar", () => ({
  AppBar: ({ title, onBack }: { title: string; onBack: () => void }) => (
    <>
      <h1>{title}</h1>
      <button type="button" onClick={onBack}>
        Back
      </button>
    </>
  ),
}));
vi.mock("../../components/ui/AppSymbol", () => ({ SymbolView: () => null }));
vi.mock("../../components/ui/AppText", () => ({
  AppText: ({
    children,
    accessibilityRole,
  }: {
    children: ReactNode;
    accessibilityRole?: string;
  }) => <span role={accessibilityRole}>{children}</span>,
  AppTextInput: ({
    accessibilityLabel,
    value,
    onChangeText,
  }: {
    accessibilityLabel: string;
    value: string;
    onChangeText: (text: string) => void;
  }) => (
    <input
      aria-label={accessibilityLabel}
      value={value}
      onChange={(event) => onChangeText(event.currentTarget.value)}
    />
  ),
}));
vi.mock("../../components/ui/Button", () => ({
  Button: ({
    label,
    disabled,
    loading,
    onPress,
  }: {
    label: string;
    disabled?: boolean;
    loading?: boolean;
    onPress: () => void;
  }) => (
    <button type="button" disabled={disabled || loading} onClick={onPress}>
      {label}
    </button>
  ),
}));
vi.mock("../../components/ui/ScreenScrollView", () => ({
  ScreenScrollView: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
}));
vi.mock("../../components/ui/ListRow", () => ({
  ListRow: ({ label, onPress }: { label: string; onPress: () => void }) => (
    <button type="button" onClick={onPress}>
      {label}
    </button>
  ),
}));
vi.mock("./components/SettingsSection", () => ({
  SettingsSection: ({ children }: { children?: ReactNode }) => <div>{children}</div>,
}));
vi.mock("../cloud/T3ConnectProfilePage", () => ({ T3ConnectProfilePage: () => null }));
vi.mock("./HarmonyAccountEmailAddresses", () => ({ HarmonyAccountEmailAddresses: () => null }));
vi.mock("./HarmonyAccountLinkedAccounts", () => ({
  HarmonyAccountLinkedAccounts: () => null,
  HarmonyAccountPasskeys: () => null,
}));
vi.mock("./HarmonyAccountMfa", () => ({ HarmonyAccountMfa: () => null }));
vi.mock("./HarmonyAccountPassword", () => ({ HarmonyAccountPassword: () => null }));
vi.mock("./HarmonyAccountSessions", () => ({ HarmonyAccountSessions: () => null }));
vi.mock("./HarmonyAccountReverification", () => ({
  isHarmonyReverificationCancelled: () => false,
  useHarmonyAccountReverification: (run: unknown) => ({ run, prompt: null }),
}));
vi.mock("../../components/ui/Dialog", () => ({ confirm: vi.fn() }));

import { HarmonyAccountProfile } from "./HarmonyAccountProfile";

function mountProfile() {
  clerk.userId = "user";
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  const container = document.createElement("div");
  const root = createRoot(container);
  const onSignedOut = vi.fn();
  const onBack = vi.fn();
  return {
    container,
    onSignedOut,
    onBack,
    render: () =>
      act(() => root.render(<HarmonyAccountProfile onBack={onBack} onSignedOut={onSignedOut} />)),
    press: (label: string) => {
      const button = [...container.querySelectorAll("button")].find(
        (candidate) => candidate.textContent === label,
      );
      if (!button) throw new Error(`Missing button "${label}"`);
      return act(async () => button.click());
    },
    [Symbol.dispose]() {
      act(() => root.unmount());
      vi.unstubAllGlobals();
    },
  };
}

it("keeps the name draft after a failed save and retries only the changed field", async () => {
  clerk.lastName = "Lovelace";
  clerk.update.mockReset();
  clerk.update.mockRejectedValueOnce(new Error("Offline")).mockResolvedValueOnce(undefined);
  using profile = mountProfile();
  await profile.render();

  await profile.press("Manage account");
  await profile.press("Edit profile");
  const firstName = profile.container.querySelector<HTMLInputElement>(
    'input[aria-label="First name"]',
  );
  if (!firstName) throw new Error("Missing first name field");
  await act(() => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set?.call(
      firstName,
      " Augusta ",
    );
    firstName.dispatchEvent(new Event("input", { bubbles: true }));
  });

  await profile.press("Save changes");
  expect(profile.container.querySelector('[role="alert"]')).not.toBeNull();
  expect(firstName.value).toBe(" Augusta ");
  clerk.lastName = "Byron";
  await profile.render();
  await profile.press("Save changes");
  expect(clerk.update.mock.calls).toEqual([[{ firstName: "Augusta" }], [{ firstName: "Augusta" }]]);
  expect(profile.container.querySelector("input")).toBeNull();
});

it("uploads a bounded profile image and returns to the account menu", async () => {
  photo.pick.mockResolvedValueOnce({
    assets: [{ uri: "file:///picked.jpg", width: 1200, height: 600 }],
  });
  clerk.setProfileImage.mockReset();
  clerk.reload.mockReset();
  photo.deleteTemporary.mockReset();
  using profile = mountProfile();
  await profile.render();
  await profile.press("Manage account");
  await profile.press("Change profile photo");
  expect(photo.resize).toHaveBeenCalledWith({ width: 512, height: 256 });
  expect(clerk.setProfileImage).toHaveBeenCalledWith({ file: "data:image/jpeg;base64,AA==" });
  expect(clerk.reload).toHaveBeenCalledOnce();
  expect(photo.deleteTemporary).toHaveBeenCalledOnce();
  await profile.press("Back");
  expect(profile.onBack).not.toHaveBeenCalled();
  expect(profile.container.textContent).toContain("Manage account");
});

it("requires explicit confirmation before requesting account deletion", async () => {
  clerk.deleteSelfEnabled = true;
  clerk.delete.mockReset();
  try {
    using profile = mountProfile();
    await profile.render();
    await profile.press("Security");
    await profile.press("Delete account");
    await profile.press("Delete account");
    expect(clerk.delete).not.toHaveBeenCalled();
    const input = profile.container.querySelector<HTMLInputElement>(
      '[aria-label="Confirm account deletion"]',
    );
    if (!input) throw new Error("Missing confirmation field");
    await act(() => {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set?.call(
        input,
        "Delete account",
      );
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });
    await profile.press("Delete account");
    expect(clerk.delete).toHaveBeenCalledOnce();
    expect(profile.onSignedOut).toHaveBeenCalledOnce();
  } finally {
    clerk.deleteSelfEnabled = false;
  }
});

it("keeps the account page open if sign-out fails", async () => {
  clerk.lastName = "Lovelace";
  clerk.signOut.mockReset();
  clerk.signOut.mockRejectedValueOnce(new Error("Offline")).mockResolvedValueOnce(undefined);
  using profile = mountProfile();
  await profile.render();

  await profile.press("Sign out");
  expect(profile.container.querySelector('[role="alert"]')).not.toBeNull();
  expect(profile.onSignedOut).not.toHaveBeenCalled();
  await profile.press("Sign out");
  expect(profile.onSignedOut).toHaveBeenCalledOnce();
});
