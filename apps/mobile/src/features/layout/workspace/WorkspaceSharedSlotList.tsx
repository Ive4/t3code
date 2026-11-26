import { IssuesScreen } from "../../issues/IssuesScreen";
import { PullRequestsScreen } from "../../pull-requests/PullRequestsScreen";
import type { SharedSlotTab } from "./navigation-tab-order";

export function WorkspaceSharedSlotList({ tab }: { readonly tab: SharedSlotTab }) {
  return tab === "issues" ? <IssuesScreen /> : <PullRequestsScreen />;
}
