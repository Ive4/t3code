export function derToJose(der: Uint8Array): Uint8Array {
  const signature = new Uint8Array(64);
  if (der.length < 8 || der.length > 72 || der[0] !== 0x30 || der[1] !== der.length - 2) {
    throw new Error("Invalid ES256 signature");
  }

  let offset = 2;
  for (let outputOffset = 0; outputOffset < signature.length; outputOffset += 32) {
    const size = der[offset + 1];
    const start = offset + 2;
    const first = der[start];
    const second = der[start + 1];
    if (
      der[offset] !== 0x02 ||
      size === undefined ||
      size < 1 ||
      size > 33 ||
      start + size > der.length ||
      first === undefined ||
      first >= 0x80 ||
      (first === 0 && (size === 1 || second === undefined || second < 0x80)) ||
      (size === 33 && first !== 0)
    ) {
      throw new Error("Invalid ES256 signature");
    }
    offset = start + size;
    const magnitude = der.subarray(start + (first === 0 ? 1 : 0), offset);
    signature.set(magnitude, outputOffset + 32 - magnitude.length);
  }
  if (offset !== der.length) throw new Error("Invalid ES256 signature");
  return signature;
}
