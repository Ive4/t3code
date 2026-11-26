import { TurboModuleRegistry, type TurboModule } from "react-native";
import {
  createHarmonyUsageWidgetData,
  type SubscriptionUsageSnapshot,
} from "./subscriptionUsageSnapshot";

interface HarmonyUsageWidget extends TurboModule {
  publish(data: string): Promise<void>;
}

export function publishSubscriptionUsage(snapshot: SubscriptionUsageSnapshot) {
  return TurboModuleRegistry.getEnforcing<HarmonyUsageWidget>("T3UsageWidget").publish(
    JSON.stringify(createHarmonyUsageWidgetData(snapshot)),
  );
}
