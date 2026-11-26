import { IssuesScreen } from "../../issues/IssuesScreen";
import { PullRequestsScreen } from "../../pull-requests/PullRequestsScreen";
import { ListSearchToolbar } from "./ListSearchToolbar";
import type { SharedSlotTab } from "./navigation-tab-order";

export function WorkspaceSharedSlotList({ tab }: { readonly tab: SharedSlotTab }) {
  const List = tab === "issues" ? IssuesScreen : PullRequestsScreen;
  return (
    <List
      renderFrame={(filters, list) => (
        <>
          <ListSearchToolbar tab={tab} filters={filters} showConnectionStatus={false} />
          {list}
        </>
      )}
    />
  );
}
