import { useGT } from "gt-react-native";

import { AppText as Text } from "../../components/ui/AppText";
import { SettingsScreen } from "./components/SettingsScreen";

export function SettingsVoiceRouteScreen() {
  const gt = useGT();
  return (
    <SettingsScreen title={gt("Voice")}>
      <Text className="px-5 pt-4 text-sm text-foreground-muted">
        {gt("Voice transcription is not available.")}
      </Text>
    </SettingsScreen>
  );
}
