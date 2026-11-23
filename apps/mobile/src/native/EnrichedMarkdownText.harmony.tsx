import type { ListItem, Root, RootContent } from "mdast";
import { Fragment, useMemo, type ReactNode } from "react";
import { ScrollView, StyleSheet, Text, View, type TextStyle } from "react-native";
import { ENRICHED_INLINE_FILE_LINK_REGEX } from "../lib/enrichedLinkPresentation";
import {
  markdownWithFileEmbeds,
  markdownWithInlineFileLinks,
  parseMarkdownDocument,
} from "../lib/markdownDocument";
import type { SelectableMarkdownTextProps } from "./SelectableMarkdownText.types";

function prepareDocument(
  markdown: string,
  fileEmbedLabel: SelectableMarkdownTextProps["fileEmbedLabel"],
) {
  const content = markdownWithInlineFileLinks(markdown, ENRICHED_INLINE_FILE_LINK_REGEX);
  const files = fileEmbedLabel ? markdownWithFileEmbeds(content, fileEmbedLabel) : undefined;
  const root = parseMarkdownDocument(files?.markdown ?? content);
  const links = new Map<string, string>();
  const tasks = new Map<ListItem, number>();
  function visit(node: Root | RootContent) {
    if (node.type === "definition" && !links.has(node.identifier)) {
      links.set(node.identifier, node.url);
    }
    if (node.type === "listItem" && typeof node.checked === "boolean") {
      tasks.set(node, tasks.size);
    }
    if ("children" in node) node.children.forEach(visit);
  }
  visit(root);
  return { root, links, tasks, fileHrefs: files?.fileHrefs };
}

export function MobileEnrichedMarkdownText(props: SelectableMarkdownTextProps) {
  const { root, links, tasks, fileHrefs } = useMemo(
    () => prepareDocument(props.markdown, props.fileEmbedLabel),
    [props.markdown, props.fileEmbedLabel],
  );
  const theme = props.textStyle;
  const body: TextStyle = {
    color: theme.color,
    fontSize: theme.fontSize,
    lineHeight: theme.lineHeight,
    textAlign: props.textAlign,
    writingDirection: props.writingDirection,
  };

  function link(href: string | undefined, children: ReactNode, image = false) {
    if (!href) return children;
    const customization = props.linkCustomization?.(href);
    const label = customization?.label ?? children;
    const onPress =
      image || fileHrefs?.has(href) ? (props.onImagePress ?? props.onLinkPress) : props.onLinkPress;
    return (
      <Text
        accessibilityRole={onPress ? "link" : undefined}
        onPress={onPress ? () => onPress(href) : undefined}
        style={{ color: customization?.color ?? theme.linkColor }}
      >
        {label}
      </Text>
    );
  }

  function inline(node: RootContent): ReactNode {
    switch (node.type) {
      case "text":
        return props.preserveSoftBreaks ? node.value : node.value.replace(/\n/g, " ");
      case "break":
        return "\n";
      case "strong":
        return (
          <Text style={{ color: theme.strongColor, fontWeight: "bold" }}>
            {nodes(node.children, inline)}
          </Text>
        );
      case "emphasis":
        return <Text style={styles.emphasis}>{nodes(node.children, inline)}</Text>;
      case "delete":
        return <Text style={styles.strike}>{nodes(node.children, inline)}</Text>;
      case "inlineCode":
        return (
          <Text style={[styles.monospace, { color: theme.inlineCodeColor }]}>{node.value}</Text>
        );
      case "link":
        return link(node.url, nodes(node.children, inline));
      case "linkReference":
        return link(links.get(node.identifier), nodes(node.children, inline));
      case "image":
        return link(node.url, node.alt || node.url, true);
      case "imageReference": {
        const href = links.get(node.identifier);
        return link(href, node.alt || href, true);
      }
      default:
        return null;
    }
  }

  function block(node: RootContent): ReactNode {
    switch (node.type) {
      case "paragraph": {
        const image = node.children.length === 1 ? node.children[0] : undefined;
        if (image?.type === "image" || image?.type === "imageReference") {
          const href = image.type === "image" ? image.url : links.get(image.identifier);
          if (href) {
            const media = props.renderImage?.({
              href,
              alt: image.alt ?? null,
              title: image.type === "image" ? (image.title ?? null) : null,
            });
            if (media != null) return media;
          }
        }
        return (
          <Text selectable style={body}>
            {nodes(node.children, inline)}
          </Text>
        );
      }
      case "heading": {
        const fontSize =
          theme.headingFontSizes?.[node.depth - 1] ?? theme.fontSize * (1.6 - node.depth * 0.1);
        return (
          <Text
            accessibilityRole="header"
            selectable
            style={[
              body,
              {
                color: theme.strongColor,
                fontSize,
                fontWeight: "bold",
                lineHeight: fontSize * 1.35,
              },
            ]}
          >
            {nodes(node.children, inline)}
          </Text>
        );
      }
      case "code":
        return (
          <ScrollView
            horizontal
            style={[styles.code, { backgroundColor: theme.codeBlockBackgroundColor }]}
          >
            <Text selectable style={[body, styles.monospace, { color: theme.codeColor }]}>
              {node.value}
            </Text>
          </ScrollView>
        );
      case "blockquote":
        return (
          <View style={[styles.blocks, styles.quote, { borderStartColor: theme.quoteMarkerColor }]}>
            {nodes(node.children, block)}
          </View>
        );
      case "list":
        return (
          <View style={styles.blocks}>
            {node.children.map((item, index) => {
              const taskIndex = tasks.get(item);
              const checked = item.checked === true;
              const onToggle = props.onTaskListItemPress;
              const marker =
                taskIndex === undefined
                  ? node.ordered
                    ? `${(node.start ?? 1) + index}.`
                    : "•"
                  : checked
                    ? "☑"
                    : "☐";
              return (
                <View key={nodeKey(item)} style={styles.row}>
                  <Text
                    accessibilityRole={taskIndex === undefined ? undefined : "checkbox"}
                    accessibilityState={taskIndex === undefined ? undefined : { checked }}
                    onPress={
                      taskIndex !== undefined && onToggle
                        ? () => {
                            onToggle({
                              index: taskIndex,
                              checked: !checked,
                              text: item.children[0] ? plainText(item.children[0]) : "",
                            });
                          }
                        : undefined
                    }
                    style={[body, { color: theme.mutedColor }]}
                  >
                    {marker}
                  </Text>
                  <View style={[styles.blocks, styles.listBody]}>
                    {nodes(item.children, block)}
                  </View>
                </View>
              );
            })}
          </View>
        );
      case "table":
        return (
          <ScrollView horizontal>
            <View>
              {node.children.map((row, index) => (
                <View
                  key={nodeKey(row)}
                  style={[styles.row, styles.tableRow, { borderColor: theme.dividerColor }]}
                >
                  {row.children.map((cell) => (
                    <Text
                      key={nodeKey(cell)}
                      selectable
                      style={[body, styles.tableCell, index === 0 && { fontWeight: "bold" }]}
                    >
                      {nodes(cell.children, inline)}
                    </Text>
                  ))}
                </View>
              ))}
            </View>
          </ScrollView>
        );
      case "thematicBreak":
        return (
          <View style={{ height: StyleSheet.hairlineWidth, backgroundColor: theme.dividerColor }} />
        );
      default:
        return null;
    }
  }

  return (
    <View
      style={[
        styles.blocks,
        styles.container,
        { marginTop: props.marginTop, marginBottom: props.marginBottom },
      ]}
    >
      {nodes(root.children, block)}
    </View>
  );
}

function nodes(children: ReadonlyArray<RootContent>, render: (node: RootContent) => ReactNode) {
  return children.map((node) => <Fragment key={nodeKey(node)}>{render(node)}</Fragment>);
}

function nodeKey(node: RootContent) {
  return `${node.type}:${node.position?.start.offset}`;
}

function plainText(node: RootContent): string {
  if (node.type === "text" || node.type === "inlineCode") return node.value;
  if (node.type === "break") return "\u2028";
  return "children" in node ? node.children.map(plainText).join("") : "";
}

const styles = StyleSheet.create({
  container: { flexShrink: 1, minWidth: 0 },
  blocks: { gap: 8 },
  row: { flexDirection: "row", gap: 8 },
  listBody: { flex: 1 },
  emphasis: { fontStyle: "italic" },
  strike: { textDecorationLine: "line-through" },
  monospace: { fontFamily: "monospace" },
  code: { borderRadius: 8, padding: 12 },
  quote: { borderStartWidth: 2, paddingStart: 12 },
  tableRow: { borderBottomWidth: StyleSheet.hairlineWidth },
  tableCell: { width: 160, padding: 8 },
});
