import { useState } from "react";
import { View } from "react-native";

import { MediaVideoPlayer } from "../../components/MediaVideoPlayer";
import { VideoPreviewModal } from "../../components/ui/VideoPreviewModal";
import type { MediaVideoPreviewSource } from "../../lib/videoPreviewSource";

export function WorkspaceFileVideoPreview(props: {
  readonly name: string;
  readonly thumbnailKey: string;
  readonly uri: string | null;
  readonly source: MediaVideoPreviewSource | null;
  readonly resolvePlaybackUri: () => Promise<string | null>;
}) {
  const uri = props.uri;
  const { source } = props;
  const [expanded, setExpanded] = useState<MediaVideoPreviewSource | null>(null);

  return (
    <View className="flex-1 items-center justify-center bg-sheet p-4">
      <MediaVideoPlayer
        uri={uri}
        resolvePlaybackUri={props.resolvePlaybackUri}
        name={props.name}
        thumbnailKey={props.thumbnailKey}
        fitToVideo
        actionsSource={props.source?.actionsSource}
        onExpand={
          source ? (initialPosition) => setExpanded({ ...source, initialPosition }) : undefined
        }
      />
      {expanded ? (
        <VideoPreviewModal source={expanded} onRequestClose={() => setExpanded(null)} />
      ) : null}
    </View>
  );
}
