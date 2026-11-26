import Pdf from "react-native-pdf-jsi";

import { PreparedPdfPreview, type PreparedPdfRendererProps } from "./PreparedPdfPreview";

function AndroidPdfRenderer(props: PreparedPdfRendererProps) {
  return (
    <Pdf
      source={{ uri: props.uri }}
      initialPage={props.initialPage}
      enableAnnotationRendering
      enableDoubleTapZoom
      onLinkPress={({ url }) => props.onLink(url)}
      onError={props.onError}
      style={{ flex: 1, width: "100%" }}
    />
  );
}

export function PdfPreview(props: { readonly uri: string }) {
  return <PreparedPdfPreview uri={props.uri} Renderer={AndroidPdfRenderer} />;
}
