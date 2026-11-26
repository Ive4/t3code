import {
  createContext,
  type ReactNode,
  use,
  useEffect,
  useState,
  useSyncExternalStore,
} from "react";
import { View } from "react-native";

// RN Modals move native window focus and close the keyboard. Keep composer menus in-window.
type OverlayEntry = {
  readonly node: ReactNode;
  readonly onRequestClose?: (() => void) | undefined;
};

let nextKey = 0;

function allocateKey() {
  return nextKey++;
}

function createOverlayStore() {
  const entries = new Map<number, OverlayEntry>();
  const listeners = new Set<() => void>();
  let snapshot: ReadonlyMap<number, OverlayEntry> = new Map();
  const emit = () => {
    snapshot = new Map(entries);
    for (const listener of listeners) listener();
  };
  return {
    getSnapshot: () => snapshot,
    subscribe(listener: () => void) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    set(key: number, entry: OverlayEntry) {
      entries.set(key, entry);
      emit();
    },
    remove(key: number) {
      entries.delete(key);
      emit();
    },
    requestClose() {
      const close = Array.from(entries.values()).at(-1)?.onRequestClose;
      if (!close) return false;
      close();
      return true;
    },
  };
}

const appOverlayStore = createOverlayStore();
const OverlayContext = createContext<ReturnType<typeof createOverlayStore> | null>(null);

export function useModalOverlayScope() {
  return use(OverlayContext) !== null;
}

/** Native modals need their own overlay host and receive system Back through onRequestClose. */
export function ModalOverlayScope(props: {
  readonly children: (onRequestClose: () => void) => ReactNode;
  readonly onRequestClose: () => void;
}) {
  const [store] = useState(createOverlayStore);
  return (
    <OverlayContext value={store}>
      {props.children(() => {
        if (!store.requestClose()) props.onRequestClose();
      })}
    </OverlayContext>
  );
}

export function OverlayPortal(props: {
  readonly children: ReactNode;
  readonly onRequestClose?: () => void;
}) {
  const store = use(OverlayContext) ?? appOverlayStore;
  const [key] = useState(allocateKey);

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- projects children into the out-of-tree overlay host store after every commit
  useEffect(() => {
    store.set(key, { node: props.children, onRequestClose: props.onRequestClose });
  });

  // Removing an entry before re-projecting it would move it above newer overlays.
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- removes this entry from the overlay host store on unmount
  useEffect(() => () => store.remove(key), [key, store]);
  return null;
}

export function OverlayPortalHost() {
  const store = use(OverlayContext) ?? appOverlayStore;
  const current = useSyncExternalStore(store.subscribe, store.getSnapshot, store.getSnapshot);

  if (current.size === 0) return null;
  return (
    <View pointerEvents="box-none" className="absolute inset-0">
      {[...current.entries()].map(([key, entry]) => (
        <View key={key} pointerEvents="box-none" className="absolute inset-0">
          {entry.node}
        </View>
      ))}
    </View>
  );
}
