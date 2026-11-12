const encoder = new TextEncoder();

export async function sha256Hex(value) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function constantTimeEqual(left, right) {
  if (typeof left !== "string" || typeof right !== "string") return false;
  let difference = left.length ^ right.length;
  const maximum = Math.max(left.length, right.length);
  for (let index = 0; index < maximum; index += 1) {
    difference |= (left.charCodeAt(index % Math.max(left.length, 1)) || 0) ^
      (right.charCodeAt(index % Math.max(right.length, 1)) || 0);
  }
  return difference === 0;
}
