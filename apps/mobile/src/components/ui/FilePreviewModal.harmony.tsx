import { isInlinePdfAvailable } from "../../lib/nativeFileActions.harmony";
import { FilePreviewModal as SharedFilePreviewModal } from "./FilePreviewModal.android";
import type { FilePreviewModalProps } from "./FilePreviewModal.types";

export type {
  FilePreviewItem,
  FilePreviewSource,
  ResolvedFilePreviewSource,
} from "./FilePreviewModal.types";

export function FilePreviewModal(props: FilePreviewModalProps) {
  return (
    <SharedFilePreviewModal
      {...props}
      externalPdf={props.source?.kind === "pdf" && !isInlinePdfAvailable()}
    />
  );
}
