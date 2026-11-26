import { EnvironmentId, type WorkflowRunsSnapshot } from "@t3tools/contracts";
import * as Cause from "effect/Cause";
import { AsyncResult } from "effect/reactivity";
import { act, type ReactNode } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vite-plus/test";

const environmentId = EnvironmentId.make("test-environment");
const emptySnapshot = {
  workflows: [],
  runs: [],
  questions: [],
} satisfies WorkflowRunsSnapshot;

const fixture = vi.hoisted(() => ({
  isReady: false,
  networkStatus: "online",
  environments: [] as Array<{
    environmentId: string;
    label: string;
    entry: { enabled: boolean };
    connection: { phase: string };
  }>,
  live: [] as Array<{
    environmentId: string;
    result: AsyncResult.AsyncResult<WorkflowRunsSnapshot, never>;
  }>,
}));

vi.mock("@effect/atom-react", () => ({ useAtomValue: () => fixture.live }));
vi.mock("@react-navigation/native", () => ({ useNavigation: () => ({}) }));
vi.mock("react-native", () => ({
  Pressable: ({ children }: { children: ReactNode }) => <div>{children}</div>,
  View: ({ children }: { children: ReactNode }) => <div>{children}</div>,
}));
vi.mock("react-native-safe-area-context", () => ({ useSafeAreaInsets: () => ({ bottom: 0 }) }));
vi.mock("../../components/RelativeTime", () => ({ RelativeTime: () => null }));
vi.mock("../../components/ui/AppActivityIndicator", () => ({ AppActivityIndicator: () => null }));
vi.mock("../../components/ui/AppText", () => ({
  AppText: ({ children }: { children: ReactNode }) => <span>{children}</span>,
}));
vi.mock("../../components/ui/EmptyState", () => ({
  EmptyState: ({ title }: { title: string }) => <span>{title}</span>,
}));
vi.mock("../../components/ui/ScreenScrollView", () => ({
  ScreenScrollView: ({ children }: { children: ReactNode }) => <div>{children}</div>,
}));
vi.mock("../../components/ui/SegmentedControl", () => ({ SegmentedControl: () => null }));
vi.mock("../../state/environments", () => ({ useEnvironments: () => fixture }));
vi.mock("../../state/query", () => ({ formatEnvironmentQueryError: () => "Query failed" }));
vi.mock("../../state/server", () => ({ serverEnvironment: { workflowsLiveAcross: () => null } }));

import { WorkflowsScreen } from "./WorkflowsScreen";

it("shows loading until the saved environments and first workflow snapshot have loaded", () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  fixture.isReady = false;
  fixture.networkStatus = "online";
  fixture.environments = [];
  fixture.live = [];
  const container = document.createElement("div");
  const root = createRoot(container);
  const render = () => act(() => root.render(<WorkflowsScreen />));
  try {
    render();
    expect(container.textContent).toBe("Loading…");

    fixture.isReady = true;
    fixture.environments = [
      {
        environmentId,
        label: "Host",
        entry: { enabled: true },
        connection: { phase: "connected" },
      },
    ];
    fixture.live = [{ environmentId, result: AsyncResult.initial(true) }];
    render();
    expect(container.textContent).toBe("Loading…");

    fixture.networkStatus = "offline";
    render();
    expect(container.textContent).toBe("Environment unavailable");

    fixture.networkStatus = "online";
    fixture.live = [{ environmentId, result: AsyncResult.failure(Cause.die("Query failed")) }];
    render();
    expect(container.textContent).toBe("Query failed");

    fixture.live = [{ environmentId, result: AsyncResult.success(emptySnapshot) }];
    render();
    expect(container.textContent).toBe("No workflow runs yet");
  } finally {
    act(() => root.unmount());
  }
});
