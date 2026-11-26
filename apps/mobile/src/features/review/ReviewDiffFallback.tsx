import { LegendList, type LegendListRef } from "@legendapp/list/react-native";
import { type ReactElement, type Ref, useImperativeHandle, useMemo, useRef, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { formatDiffCount } from "@t3tools/client-runtime/diff-count";

import { SymbolView } from "../../components/ui/AppSymbol";
import { RefreshControl } from "../../components/ui/RefreshControl";
import { NativeScrollView } from "../../native/NativeScrollViewMarker";
import type { HighlightScheme } from "../../lib/highlights";
import type {
  NativeReviewDiffRow,
  NativeReviewDiffTheme,
  NativeReviewDiffViewHandle,
} from "../diffs/nativeReviewDiffSurface";
import type { NativeReviewDiffFile } from "../diffs/nativeReviewDiffTypes";
import type { createNativeReviewDiffStyle } from "./nativeReviewDiffAdapter";
import { highlightReviewFallbackLine } from "./reviewFallbackHighlight";
import { buildReviewFallbackLineTokens, buildReviewFallbackRows } from "./reviewFallbackRows";
import { DiffTokenText, REVIEW_MONO_FONT_FAMILY } from "./reviewDiffRendering";

interface ReviewDiffFallbackProps {
  readonly ref?: Ref<NativeReviewDiffViewHandle>;
  readonly rows: ReadonlyArray<NativeReviewDiffRow>;
  readonly files: ReadonlyArray<NativeReviewDiffFile>;
  readonly scheme: HighlightScheme;
  readonly collapsedFileIds: ReadonlyArray<string>;
  readonly viewedFileIds: ReadonlyArray<string>;
  readonly selectedRowIds: ReadonlyArray<string>;
  readonly theme: NativeReviewDiffTheme;
  readonly diffStyle: ReturnType<typeof createNativeReviewDiffStyle>;
  readonly initialFileId?: string | undefined;
  readonly initialRowId?: string | undefined;
  readonly listHeader: ReactElement | null;
  readonly bottomInset: number;
  readonly refreshing: boolean;
  readonly onRefresh: () => void;
  readonly onEndReached?: (() => void) | undefined;
  readonly onVisibleFileChange: (fileId: string | null) => void;
  readonly onToggleFile: (fileId: string) => void;
  readonly onToggleViewedFile: (fileId: string) => void;
  readonly canToggleViewed?: boolean;
  readonly onPressLine: (rowId: string, gesture: "tap" | "longPress") => void;
  readonly onOpenComment?: (commentId: string) => void;
  readonly onPressNotice?: (fileId: string) => void;
}

function ReviewFallbackCode(props: {
  readonly row: NativeReviewDiffRow;
  readonly language: string | undefined;
  readonly scheme: HighlightScheme;
  readonly color: string;
  readonly diffStyle: ReviewDiffFallbackProps["diffStyle"];
}) {
  const { row, language, scheme, color, diffStyle } = props;
  const tokens = useMemo(
    () =>
      buildReviewFallbackLineTokens(
        row,
        language && row.content ? highlightReviewFallbackLine(row.content, language, scheme) : null,
      ),
    [row, language, scheme],
  );
  const content = (
    <DiffTokenText
      tokens={tokens}
      fallback={row.content ?? ""}
      change={row.change}
      className={diffStyle.wordWrap ? "min-w-0 flex-1" : undefined}
      color={color}
      fontSize={diffStyle.codeFontSize}
      lineHeight={diffStyle.rowHeight}
      wordWrap={diffStyle.wordWrap}
      selectable={false}
    />
  );
  return diffStyle.wordWrap ? (
    content
  ) : (
    <ScrollView horizontal nestedScrollEnabled className="min-w-0 flex-1">
      {content}
    </ScrollView>
  );
}

export function ReviewDiffFallback({
  ref,
  rows,
  files,
  scheme,
  collapsedFileIds,
  viewedFileIds,
  selectedRowIds,
  theme,
  diffStyle,
  initialFileId,
  initialRowId,
  listHeader,
  bottomInset,
  refreshing,
  onRefresh,
  onEndReached,
  onVisibleFileChange,
  onToggleFile,
  onToggleViewedFile,
  canToggleViewed = true,
  onPressLine,
  onOpenComment,
  onPressNotice,
}: ReviewDiffFallbackProps) {
  const listRef = useRef<LegendListRef>(null);
  const lastVisibleFile = useRef<string | null>(null);
  const [collapsedComments, setCollapsedComments] = useState<ReadonlySet<string>>(() => new Set());
  const visible = useMemo(
    () =>
      buildReviewFallbackRows(rows, collapsedFileIds, {
        fileId: initialFileId,
        rowId: initialRowId,
      }),
    [rows, collapsedFileIds, initialFileId, initialRowId],
  );
  const collapsedFiles = useMemo(() => new Set(collapsedFileIds), [collapsedFileIds]);
  const viewedFiles = useMemo(() => new Set(viewedFileIds), [viewedFileIds]);
  const selectedRows = useMemo(() => new Set(selectedRowIds), [selectedRowIds]);
  const languagesByFileId = useMemo(
    () => new Map(files.map((file) => [file.id, file.language])),
    [files],
  );

  useImperativeHandle(
    ref,
    () => ({
      scrollToFile: async (fileId, animated) => {
        const index = visible.fileIndexes.get(fileId);
        if (index !== undefined) {
          await listRef.current?.scrollToIndex({ index, animated });
        }
      },
      scrollToTop: async (animated) => {
        await listRef.current?.scrollToOffset({ offset: 0, animated });
      },
    }),
    [visible.fileIndexes],
  );

  const renderRow = ({ item }: { readonly item: NativeReviewDiffRow }) => {
    const fileId = item.fileId;
    if (item.kind === "file" && fileId !== undefined) {
      const expanded = !collapsedFiles.has(fileId);
      const viewed = viewedFiles.has(fileId);
      return (
        <View
          className="mx-2 my-1 flex-row items-center rounded-lg border"
          style={{ borderColor: theme.border, backgroundColor: theme.headerBackground }}
        >
          <Pressable
            accessibilityRole="button"
            accessibilityState={{ expanded }}
            className="min-w-0 flex-1 flex-row items-center gap-2 px-3 py-2"
            onPress={() => onToggleFile(fileId)}
          >
            <SymbolView
              name={expanded ? "chevron.down" : "chevron.right"}
              size={12}
              tintColorClassName="accent-icon-muted"
            />
            <View className="min-w-0 flex-1">
              <Text style={{ color: theme.text }} numberOfLines={2}>
                {item.filePath}
              </Text>
              {item.previousPath ? (
                <Text style={{ color: theme.mutedText }} numberOfLines={1}>
                  {item.previousPath}
                </Text>
              ) : null}
              <Text style={{ color: theme.mutedText }}>
                <Text style={{ color: theme.addText }}>
                  +{formatDiffCount(item.additions ?? 0)}
                </Text>
                {"  "}
                <Text style={{ color: theme.deleteText }}>
                  -{formatDiffCount(item.deletions ?? 0)}
                </Text>
              </Text>
            </View>
          </Pressable>
          <Pressable
            accessibilityRole="checkbox"
            accessibilityState={{ checked: viewed, disabled: !canToggleViewed }}
            accessibilityLabel={item.filePath}
            className="size-11 items-center justify-center"
            disabled={!canToggleViewed}
            onPress={() => onToggleViewedFile(fileId)}
          >
            <SymbolView
              name={viewed ? "checkmark.circle" : "circle"}
              size={18}
              tintColorClassName="accent-icon-muted"
            />
          </Pressable>
        </View>
      );
    }
    if (item.kind === "comment") {
      const expanded = Boolean(onOpenComment) || !collapsedComments.has(item.id);
      return (
        <Pressable
          accessibilityRole="button"
          accessibilityState={onOpenComment ? undefined : { expanded }}
          className="mx-2 my-1 gap-1 rounded-lg border px-3 py-2"
          style={{ borderColor: theme.border, backgroundColor: theme.headerBackground }}
          onPress={() => {
            if (onOpenComment) {
              onOpenComment(item.id);
              return;
            }
            setCollapsedComments((current) => {
              const next = new Set(current);
              if (next.has(item.id)) next.delete(item.id);
              else next.add(item.id);
              return next;
            });
          }}
        >
          <View className="flex-row items-center gap-2">
            <SymbolView
              name={!onOpenComment && expanded ? "chevron.down" : "chevron.right"}
              size={12}
              tintColorClassName="accent-icon-muted"
            />
            <Text className="min-w-0 flex-1" style={{ color: theme.mutedText }}>
              {[item.commentRangeLabel, item.commentSectionTitle].filter(Boolean).join(" · ")}
            </Text>
          </View>
          {expanded ? <Text style={{ color: theme.text }}>{item.commentText}</Text> : null}
        </Pressable>
      );
    }
    if (item.kind !== "line") {
      const text = (
        <Text
          className="px-3 py-1"
          style={{
            color: item.tone === "warning" ? theme.warningText : theme.hunkText,
            backgroundColor:
              item.tone === "warning" ? theme.warningBackground : theme.hunkBackground,
            fontFamily: REVIEW_MONO_FONT_FAMILY,
            fontSize: diffStyle.hunkFontSize,
          }}
        >
          {item.text}
        </Text>
      );
      return item.actionable && fileId !== undefined && onPressNotice ? (
        <Pressable accessibilityRole="button" onPress={() => onPressNotice(fileId)}>
          {text}
        </Pressable>
      ) : (
        text
      );
    }

    const selected = selectedRows.has(item.id);
    const background =
      item.change === "add"
        ? theme.addBackground
        : item.change === "delete"
          ? theme.deleteBackground
          : theme.background;
    const changeColor =
      item.change === "add"
        ? theme.addBar
        : item.change === "delete"
          ? theme.deleteBar
          : theme.border;
    const gutterStyle = {
      width: diffStyle.gutterWidth / 2,
      color: theme.mutedText,
      fontFamily: REVIEW_MONO_FONT_FAMILY,
      fontSize: diffStyle.lineNumberFontSize,
      lineHeight: diffStyle.rowHeight,
    } as const;
    return (
      <Pressable
        accessibilityRole="button"
        accessibilityState={{ selected }}
        onPress={() => onPressLine(item.id, "tap")}
        onLongPress={() => onPressLine(item.id, "longPress")}
        className="flex-row"
        style={{
          minHeight: diffStyle.rowHeight,
          backgroundColor: selected ? theme.hunkBackground : background,
          borderLeftColor: changeColor,
          borderLeftWidth: diffStyle.changeBarWidth,
          paddingHorizontal: diffStyle.codePadding,
        }}
      >
        <Text style={gutterStyle}>{item.oldLineNumber}</Text>
        <Text style={gutterStyle}>{item.newLineNumber}</Text>
        <ReviewFallbackCode
          key={item.id}
          row={item}
          language={fileId === undefined ? undefined : languagesByFileId.get(fileId)}
          scheme={scheme}
          color={theme.text}
          diffStyle={diffStyle}
        />
      </Pressable>
    );
  };

  return (
    <LegendList
      ref={listRef}
      renderScrollComponent={NativeScrollView}
      contentInsetAdjustmentBehavior="never"
      testID="review-fallback-diff-view"
      data={visible.rows}
      initialScrollIndex={visible.initialScrollIndex}
      extraData={[
        collapsedFiles,
        viewedFiles,
        collapsedComments,
        selectedRows,
        languagesByFileId,
        scheme,
        theme,
        diffStyle,
        onPressLine,
        onToggleFile,
        onToggleViewedFile,
        canToggleViewed,
        onOpenComment,
        onPressNotice,
      ]}
      keyExtractor={(item) => item.id}
      renderItem={renderRow}
      estimatedItemSize={diffStyle.rowHeight}
      getItemType={(item) => item.kind}
      recycleItems
      ListHeaderComponent={listHeader ?? undefined}
      contentContainerStyle={{ paddingBottom: bottomInset }}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      onEndReached={onEndReached}
      onViewableItemsChanged={({ viewableItems }) => {
        const first = viewableItems[0];
        const fileId = first?.item.fileId ?? null;
        if (fileId !== lastVisibleFile.current) {
          lastVisibleFile.current = fileId;
          onVisibleFileChange(fileId);
        }
      }}
    />
  );
}
