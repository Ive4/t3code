const collator =
  typeof globalThis.Intl?.Collator === "function"
    ? new Intl.Collator(undefined, { numeric: true, sensitivity: "base" })
    : null;

export const compareFileNames =
  collator?.compare ??
  ((left: string, right: string) => {
    const leftParts = left.toLowerCase().split(/(\d+)/);
    const rightParts = right.toLowerCase().split(/(\d+)/);
    for (let index = 0; index < Math.min(leftParts.length, rightParts.length); index += 1) {
      let a = leftParts[index]!;
      let b = rightParts[index]!;
      if (index % 2 === 1) {
        a = a.replace(/^0+(?=\d)/, "");
        b = b.replace(/^0+(?=\d)/, "");
        if (a.length !== b.length) return a.length - b.length;
      }
      if (a !== b) return a < b ? -1 : 1;
    }
    return leftParts.length - rightParts.length;
  });
