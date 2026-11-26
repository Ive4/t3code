import { useEffect, useEffectEvent } from "react";
import {
  DeviceEventEmitter,
  TurboModuleRegistry,
  useWindowDimensions,
  type TurboModule,
} from "react-native";

import type { VerticalHinge } from "../lib/layout";

interface FoldPostureModule extends TurboModule {
  readVerticalHinge(): Promise<VerticalHinge | null>;
}

export function AndroidHingeObserver(props: {
  readonly onChange: (hinge: VerticalHinge | null, windowHinge: VerticalHinge | null) => void;
}) {
  const { width, height } = useWindowDimensions();
  const publish = useEffectEvent((hinge: VerticalHinge | null) => props.onChange(hinge, hinge));
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- The native crease uses the current window frame.
  useEffect(() => {
    const native = TurboModuleRegistry.get<FoldPostureModule>("T3FoldPosture");
    if (!native || width <= 0 || height <= 0) return;

    let request = 0;
    const update = () => {
      const generation = ++request;
      void native.readVerticalHinge().then(
        (hinge) => {
          if (request === generation) publish(hinge);
        },
        () => {
          if (request === generation) publish(null);
        },
      );
    };
    const subscription = DeviceEventEmitter.addListener("T3FoldPostureChanged", update);
    update();
    return () => {
      request++;
      subscription.remove();
    };
  }, [height, width]);
  return null;
}
