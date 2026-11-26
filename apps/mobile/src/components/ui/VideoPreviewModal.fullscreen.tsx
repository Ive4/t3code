import { errorDisplayMessage } from "@t3tools/client-runtime/errors";
import { videoMimeType } from "@t3tools/shared/video";
import { T, useGT, useMessages } from "gt-react-native";
import { Modal, Pressable, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { AppActivityIndicator } from "./AppActivityIndicator";
import { useLocalAttachmentPreview } from "../../lib/localAttachmentPreview";
import { usePreviewPresentation, videoPreviewKey } from "../../lib/previewPresentation";
import { useMediaActions } from "../../state/mediaActions";
import { type MediaActionsSource } from "../../lib/mediaActionsSource";
import {
  mediaVideoPreviewUri,
  mediaVideoThumbnailKey,
  type LocalVideoPreviewSource,
  type MediaVideoPreviewSource,
  type VideoPreviewSource,
} from "../../lib/videoPreviewSource";
import { useAssetUrlState, useRefreshAssetUrl } from "../../state/assets";
import { usePreparedConnection } from "../../state/session";
import { AppText } from "./AppText";
import { MediaPreviewHeader } from "../MediaPreviewHeader";
import { MediaVideoPlayer } from "../MediaVideoPlayer";
import { ModalOverlayScope, OverlayPortalHost } from "./OverlayPortal";

interface PresentationProps {
  readonly harmony?: boolean | undefined;
  readonly onRequestClose: () => void;
}

interface PlaybackState {
  readonly uri: string | null;
  readonly resolvePlaybackUri?: () => Promise<string | null>;
  readonly unavailable: boolean;
  readonly unavailableDetail?: string | undefined;
  readonly error: string | null;
  readonly actionsSource: MediaActionsSource | undefined;
}

function useMediaPlayback(source: MediaVideoPreviewSource): PlaybackState {
  const environmentId = "environmentId" in source ? source.environmentId : null;
  const resource = "resource" in source ? source.resource : null;
  const connection = usePreparedConnection(environmentId);
  const asset = useAssetUrlState(environmentId, resource);
  const gt = useGT();
  const refreshAssetUrl = useRefreshAssetUrl(environmentId, resource);
  const uri = mediaVideoPreviewUri(source, asset._tag === "Success" ? asset.url : null);
  return {
    uri,
    ...(resource !== null
      ? { resolvePlaybackUri: async () => mediaVideoPreviewUri(source, await refreshAssetUrl()) }
      : {}),
    unavailable:
      uri === null &&
      environmentId !== null &&
      (connection._tag === "None" || asset._tag === "Failure"),
    unavailableDetail:
      asset._tag === "Failure" && asset.reason === "missing-file-access"
        ? gt("This connection cannot read host files. Pair again with a new link to view it.")
        : undefined,
    error: null,
    actionsSource: source.actionsSource ?? source,
  };
}

function useLocalPlayback(source: LocalVideoPreviewSource): PlaybackState {
  const gt = useGT();
  const messages = useMessages();
  const { attachment } = source;
  const preview = useLocalAttachmentPreview(attachment);
  const { uri } = preview;
  const error = preview.error
    ? errorDisplayMessage(preview.error, messages) || gt("Could not load this video.")
    : null;
  const mimeType = videoMimeType(attachment) ?? attachment.mimeType;
  return {
    uri,
    unavailable: error !== null,
    error,
    actionsSource:
      uri === null
        ? undefined
        : {
            name: attachment.name,
            mimeType,
            attachment,
            ...(source.sourceIdentifier ? { sourceIdentifier: source.sourceIdentifier } : {}),
          },
  };
}

function MediaPreviewModal(
  props: PresentationProps & { readonly source: MediaVideoPreviewSource },
) {
  return (
    <OpenVideoPreviewModal
      name={props.source.name}
      thumbnailKey={mediaVideoThumbnailKey(props.source)}
      playback={useMediaPlayback(props.source)}
      initialPosition={props.source.initialPosition}
      harmony={props.harmony}
      onRequestClose={props.onRequestClose}
    />
  );
}

function LocalPreviewModal(
  props: PresentationProps & { readonly source: LocalVideoPreviewSource },
) {
  return (
    <OpenVideoPreviewModal
      name={props.source.attachment.name}
      thumbnailKey={`local:${props.source.attachment.id}`}
      playback={useLocalPlayback(props.source)}
      harmony={props.harmony}
      onRequestClose={props.onRequestClose}
    />
  );
}

function OpenVideoPreviewModal(
  props: PresentationProps & {
    readonly name: string;
    readonly thumbnailKey: string;
    readonly playback: PlaybackState;
    readonly initialPosition?: number | undefined;
  },
) {
  const gt = useGT();
  const { playback } = props;
  const insets = useSafeAreaInsets();
  const mediaActions = useMediaActions(playback.actionsSource, props.onRequestClose);
  const save = mediaActions.actions.find((action) => action.id === "save");

  const renderModal = (onRequestClose: () => void) => (
    <Modal
      visible
      animationType="fade"
      presentationStyle="fullScreen"
      onRequestClose={onRequestClose}
      statusBarTranslucent
      navigationBarTranslucent
    >
      <View
        className="flex-1 bg-black"
        style={{ paddingTop: insets.top, paddingBottom: insets.bottom }}
      >
        <MediaPreviewHeader
          title={props.name}
          media={mediaActions}
          closeAccessibilityLabel={gt("Close video")}
          onClose={props.onRequestClose}
        />
        {playback.uri === null && !playback.unavailable ? (
          <View className="flex-1 items-center justify-center gap-3 px-6">
            <AppActivityIndicator color="#ffffff" />
            <AppText className="text-sm text-white/80">
              <T>Loading video...</T>
            </AppText>
          </View>
        ) : (
          <MediaVideoPlayer
            uri={playback.uri}
            resolvePlaybackUri={playback.resolvePlaybackUri}
            name={props.name}
            thumbnailKey={props.thumbnailKey}
            unavailable={playback.unavailable}
            unavailableDetail={playback.unavailableDetail}
            paused={mediaActions.sharing}
            expanded
            autoPlay
            fullscreen={props.harmony}
            initialPosition={props.initialPosition}
          />
        )}
        {playback.error ? (
          <AppText accessibilityRole="alert" className="px-4 pb-3 text-sm text-white/80">
            {playback.error}
          </AppText>
        ) : null}
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={gt("Save or share video")}
          disabled={playback.uri === null || !save || save.disabled === true}
          onPress={mediaActions.share}
          className="mx-4 my-3 min-h-12 items-center justify-center rounded-xl bg-white/15 px-4"
        >
          <AppText className="font-t3-medium text-base text-white">
            {mediaActions.sharing ? gt("Opening share sheet...") : gt("Save or share video")}
          </AppText>
        </Pressable>
        {props.harmony ? <OverlayPortalHost /> : null}
      </View>
    </Modal>
  );
  return props.harmony ? (
    <ModalOverlayScope onRequestClose={props.onRequestClose}>{renderModal}</ModalOverlayScope>
  ) : (
    renderModal(props.onRequestClose)
  );
}

export function VideoPreviewModal(
  props: PresentationProps & {
    readonly source: VideoPreviewSource | null;
  },
) {
  usePreviewPresentation(
    props.source === null ? null : videoPreviewKey(props.source),
    props.onRequestClose,
  );
  const { source } = props;
  if (source === null) return null;
  return source.type === "local" ? (
    <LocalPreviewModal
      key={videoPreviewKey(source)}
      source={source}
      harmony={props.harmony}
      onRequestClose={props.onRequestClose}
    />
  ) : (
    <MediaPreviewModal
      key={videoPreviewKey(source)}
      source={source}
      harmony={props.harmony}
      onRequestClose={props.onRequestClose}
    />
  );
}
