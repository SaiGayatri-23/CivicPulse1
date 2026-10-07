// Aadhaar numbers carry a Verhoeff check digit (UIDAI's published scheme). This catches typos and
// made-up numbers on the device, without the number ever leaving the browser. It confirms the
// number is well-formed, not that it belongs to the person; that part is the admin's document review.
const d = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 2, 3, 4, 0, 6, 7, 8, 9, 5], [2, 3, 4, 0, 1, 7, 8, 9, 5, 6], [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
  [4, 0, 1, 2, 3, 9, 5, 6, 7, 8], [5, 9, 8, 7, 6, 0, 4, 3, 2, 1], [6, 5, 9, 8, 7, 1, 0, 4, 3, 2], [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
  [8, 7, 6, 5, 9, 3, 2, 1, 0, 4], [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
];
const p = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 5, 7, 6, 2, 8, 3, 0, 9, 4], [5, 8, 0, 3, 7, 9, 6, 1, 4, 2], [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
  [9, 4, 5, 3, 1, 2, 6, 8, 7, 0], [4, 2, 8, 6, 5, 7, 3, 9, 0, 1], [2, 7, 9, 3, 8, 0, 6, 4, 1, 5], [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
];

/** True when `num` is 12 digits, does not start with 0 or 1, and its Verhoeff check digit is right. */
export function isValidAadhaar(num: string): boolean {
  const s = num.replace(/\s/g, '');
  if (!/^[2-9][0-9]{11}$/.test(s)) return false;
  let c = 0;
  const digits = s.split('').reverse().map(Number);
  for (let i = 0; i < digits.length; i++) c = d[c][p[i % 8][digits[i]]];
  return c === 0;
}

export const aadhaarLast4 = (num: string) => num.replace(/\s/g, '').slice(-4);
