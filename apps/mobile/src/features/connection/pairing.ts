import { readPairingQrPayload } from "@t3tools/shared/remote";
import * as Schema from "effect/Schema";
import { msg } from "gt-react-native";

import { m } from "../../i18n/messages";

export { buildPairingUrl, parsePairingUrl } from "@t3tools/shared/remote";

export class PairingQrPayloadEmptyError extends Schema.TaggedError<PairingQrPayloadEmptyError>()(
  "PairingQrPayloadEmptyError",
  {},
) {
  override get message(): string {
    return m(msg("Scanned QR code did not contain a pairing URL."));
  }
}

export function extractPairingUrlFromQrPayload(payload: string): string {
  const pairingUrl = readPairingQrPayload(payload);
  if (!pairingUrl) throw new PairingQrPayloadEmptyError({});
  return pairingUrl;
}
