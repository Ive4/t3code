import { useClerk } from "@clerk/expo";
import type { UserResource } from "@clerk/expo/types";
import { useGT } from "gt-react-native";
import { useRef, useState } from "react";
import { Image, View } from "react-native";

import { SymbolView } from "../../components/ui/AppSymbol";
import { AppText } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";
import * as Dialog from "../../components/ui/Dialog";

export function HarmonyAccountAvatarEditor({ user }: { readonly user: UserResource }) {
  const gt = useGT();
  const clerk = useClerk();
  const [action, setAction] = useState<"select" | "remove" | null>(null);
  const [failed, setFailed] = useState(false);
  const pending = useRef(false);

  async function updatePhoto(kind: "select" | "remove", sessionId: string | undefined) {
    const isCurrent = () =>
      sessionId !== undefined && clerk.session?.id === sessionId && clerk.user?.id === user.id;
    if (pending.current || !isCurrent()) return;
    pending.current = true;
    setAction(kind);
    setFailed(false);
    try {
      const file = kind === "remove" ? null : await selectPhoto();
      if (file === undefined || !isCurrent()) return;
      await user.setProfileImage({ file });
      if (isCurrent()) await user.reload();
    } catch {
      if (isCurrent()) setFailed(true);
    } finally {
      pending.current = false;
      setAction(null);
    }
  }

  return (
    <View className="items-center gap-3">
      <View className="size-16 items-center justify-center overflow-hidden rounded-full bg-subtle">
        <SymbolView
          name="person.crop.circle"
          size={32}
          tintColorClassName="accent-foreground-muted"
        />
        {user.imageUrl ? (
          <Image accessible={false} source={{ uri: user.imageUrl }} className="absolute size-16" />
        ) : null}
      </View>
      <View className="flex-row flex-wrap justify-center gap-2">
        <Button
          label={gt("Change profile photo")}
          size="compact"
          disabled={action !== null}
          loading={action === "select"}
          onPress={() => void updatePhoto("select", clerk.session?.id)}
        />
        {user.hasImage ? (
          <Button
            label={gt("Remove photo")}
            size="compact"
            tone="text"
            disabled={action !== null}
            loading={action === "remove"}
            onPress={() => {
              const sessionId = clerk.session?.id;
              Dialog.confirm({
                title: gt("Remove profile photo?"),
                confirmText: gt("Remove"),
                destructive: true,
                onConfirm: () => void updatePhoto("remove", sessionId),
              });
            }}
          />
        ) : null}
      </View>
      {failed ? (
        <AppText accessibilityRole="alert" className="text-danger-foreground">
          {gt("Could not update your profile photo. Try again.")}
        </AppText>
      ) : null}
    </View>
  );
}

async function selectPhoto(): Promise<string | undefined> {
  const { launchImageLibraryAsync } = await import("expo-image-picker");
  const result = await launchImageLibraryAsync({ mediaTypes: ["images"] });
  const selected = result.assets?.[0];
  if (!selected) return;
  const [{ ImageManipulator, SaveFormat }, { File }] = await Promise.all([
    import("expo-image-manipulator"),
    import("expo-file-system"),
  ]);
  const size =
    selected.width > 0 && selected.height > 0 ? selected : await Image.getSize(selected.uri);
  const scale = Math.min(1, 512 / Math.max(size.width, size.height));
  const rendered = await ImageManipulator.manipulate(selected.uri)
    .resize({
      width: Math.max(1, Math.round(size.width * scale)),
      height: Math.max(1, Math.round(size.height * scale)),
    })
    .renderAsync();
  const photo = await rendered.saveAsync({ format: SaveFormat.JPEG, compress: 0.85, base64: true });
  const temporary = new File(photo.uri);
  try {
    if (!photo.base64) throw new Error("The photo could not be encoded.");
    return "data:image/jpeg;base64," + photo.base64;
  } finally {
    try {
      if (temporary.exists) temporary.delete();
    } catch {
      // Cache cleanup must not prevent the photo upload.
    }
  }
}
