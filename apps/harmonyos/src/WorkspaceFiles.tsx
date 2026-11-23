import { useAtomValue } from "@effect/atom-react";
import { sessionDeniesScope } from "@t3tools/client-runtime/state/session";
import { AuthFilesystemReadScope, type EnvironmentId } from "@t3tools/contracts";
import { AsyncResult } from "effect/reactivity";
import { useState } from "react";
import {
  ActivityIndicator,
  // oxlint-disable-next-line eslint/no-restricted-imports -- The mobile native scroll view targets iOS and Android.
  FlatList,
  StyleSheet,
  Text,
} from "react-native";

import { text } from "./labels";
import { files, session } from "./runtime";
import { ListRow, PageBody, PageText, Toolbar, useWorkspaceTheme } from "./WorkspaceUi";

export function WorkspaceFiles({
  environmentId,
  cwd,
  back,
}: {
  readonly environmentId: EnvironmentId;
  readonly cwd: string;
  readonly back: () => void;
}) {
  const auth = useAtomValue(session.sessionStateAtom(environmentId));
  const [directory, setDirectory] = useState("");
  const [file, setFile] = useState<string | null>(null);
  if (sessionDeniesScope(auth, AuthFilesystemReadScope)) {
    return (
      <>
        <Toolbar title={text.files} back={back} />
        <PageBody>
          <PageText muted>{text.unavailable}</PageText>
        </PageBody>
      </>
    );
  }
  return file !== null ? (
    <FilePreview environmentId={environmentId} cwd={cwd} path={file} back={() => setFile(null)} />
  ) : (
    <Directory
      environmentId={environmentId}
      cwd={cwd}
      directory={directory}
      back={
        directory
          ? () => setDirectory(directory.slice(0, Math.max(0, directory.lastIndexOf("/"))))
          : back
      }
      openDirectory={setDirectory}
      openFile={setFile}
    />
  );
}

function Directory({
  environmentId,
  cwd,
  directory,
  back,
  openDirectory,
  openFile,
}: {
  readonly environmentId: EnvironmentId;
  readonly cwd: string;
  readonly directory: string;
  readonly back: () => void;
  readonly openDirectory: (path: string) => void;
  readonly openFile: (path: string) => void;
}) {
  const result = useAtomValue(
    files.list({ environmentId, input: { cwd, directoryPath: directory } }),
  );
  const value = AsyncResult.getOrElse(result, () => null);
  return (
    <>
      <Toolbar title={directory || text.files} back={back} />
      <FlatList
        data={value?.entries ?? []}
        keyExtractor={(entry) => entry.path}
        style={styles.list}
        contentContainerStyle={styles.listContent}
        ListHeaderComponent={value?.truncated ? <PageText muted>{text.truncated}</PageText> : null}
        ListEmptyComponent={
          result._tag === "Initial" ? (
            <ActivityIndicator accessibilityLabel={text.loading} />
          ) : result._tag === "Failure" ? (
            <PageText error>{text.unableToLoad}</PageText>
          ) : (
            <PageText muted>{text.emptyDirectory}</PageText>
          )
        }
        renderItem={({ item }) => {
          const name = item.path.slice(item.path.lastIndexOf("/") + 1);
          const isFolder = item.kind === "directory";
          return (
            <ListRow
              title={isFolder ? name + "/" : name}
              onPress={() => (isFolder ? openDirectory(item.path) : openFile(item.path))}
            />
          );
        }}
      />
    </>
  );
}

function FilePreview({
  environmentId,
  cwd,
  path,
  back,
}: {
  readonly environmentId: EnvironmentId;
  readonly cwd: string;
  readonly path: string;
  readonly back: () => void;
}) {
  const result = useAtomValue(files.read({ environmentId, input: { cwd, relativePath: path } }));
  const file = AsyncResult.getOrElse(result, () => null);
  const limit = 100_000;
  const theme = useWorkspaceTheme();
  return (
    <>
      <Toolbar title={path.slice(path.lastIndexOf("/") + 1)} back={back} />
      <PageBody>
        <PageText muted>{path}</PageText>
        {result._tag === "Initial" && <ActivityIndicator accessibilityLabel={text.loading} />}
        {result._tag === "Failure" && <PageText error>{text.unableToLoadFile}</PageText>}
        {file && (file.truncated || file.contents.length > limit) && (
          <PageText muted>{text.truncated}</PageText>
        )}
        {file && (
          <Text selectable style={[styles.contents, { color: theme["--color-foreground"] }]}>
            {file.contents.slice(0, limit)}
          </Text>
        )}
      </PageBody>
    </>
  );
}

const styles = StyleSheet.create({
  list: { flex: 1 },
  listContent: { padding: 16 },
  contents: { fontFamily: "monospace", fontSize: 13, lineHeight: 19 },
});
