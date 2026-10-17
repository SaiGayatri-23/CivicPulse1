// Pixelation helpers shared by the reporter's photo editor, the automatic privacy blur that runs
// when a photo is chosen, and the admin's blur tool. Pixelation is used instead of CSS blur
// because it works in every browser and cannot be undone once the image is re-encoded.

/** Pixelate an elliptical spot of radius `r` (pixels) centred on (cx, cy). */
export function pixelate(ctx: CanvasRenderingContext2D, cx: number, cy: number, r: number) {
  const x = Math.max(0, Math.round(cx - r)), y = Math.max(0, Math.round(cy - r));
  const w = Math.min(ctx.canvas.width - x, Math.round(r * 2)), h = Math.min(ctx.canvas.height - y, Math.round(r * 2));
  pixelateRect(ctx, x, y, w, h, true);
}

/** Pixelate a rectangle (optionally clipped to an ellipse) and draw a thin ring so the spot is visible. */
export function pixelateRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, ellipse = false) {
  if (w <= 0 || h <= 0) return;
  const block = Math.max(6, Math.round(Math.max(w, h) / 10));
  const small = document.createElement('canvas');
  small.width = Math.max(1, Math.round(w / block));
  small.height = Math.max(1, Math.round(h / block));
  small.getContext('2d')!.drawImage(ctx.canvas, x, y, w, h, 0, 0, small.width, small.height);
  ctx.save();
  if (ellipse) { ctx.beginPath(); ctx.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2); ctx.clip(); }
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(small, 0, 0, small.width, small.height, x, y, w, h);
  ctx.restore();
  ctx.save();
  ctx.beginPath();
  if (ellipse) ctx.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2); else ctx.rect(x, y, w, h);
  ctx.lineWidth = Math.max(2, Math.round(ctx.canvas.width / 400));
  ctx.strokeStyle = 'rgba(255,255,255,0.9)';
  ctx.stroke();
  ctx.restore();
}

/** A detected face or number plate: box is [ymin, xmin, ymax, xmax] on a 0-1000 scale. */
export type PrivacyRegion = { label: 'face' | 'number_plate'; box: [number, number, number, number] };

/** Return a copy of `file` with every region pixelated (faces as ellipses, plates as rectangles). */
export async function pixelateRegions(file: Blob, regions: PrivacyRegion[]): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 1600 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  const ctx = canvas.getContext('2d')!;
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  for (const r of regions) {
    const [ymin, xmin, ymax, xmax] = r.box.map((v) => Math.min(1000, Math.max(0, v)));
    // Pad a little so the edges of the plate or face are covered too.
    const pad = r.label === 'face' ? 0.15 : 0.1;
    const bw = (xmax - xmin) / 1000 * canvas.width, bh = (ymax - ymin) / 1000 * canvas.height;
    const x = Math.round(xmin / 1000 * canvas.width - bw * pad), y = Math.round(ymin / 1000 * canvas.height - bh * pad);
    const w = Math.round(bw * (1 + 2 * pad)), h = Math.round(bh * (1 + 2 * pad));
    pixelateRect(ctx, Math.max(0, x), Math.max(0, y), Math.min(canvas.width - Math.max(0, x), w), Math.min(canvas.height - Math.max(0, y), h), r.label === 'face');
  }
  return new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('Could not process the photo.'))), 'image/jpeg', 0.9));
}

/** Small JPEG copy for the AI request (keeps it fast; the full photo is never sent). */
export async function downscaleForAI(file: Blob): Promise<{ base64: string; mime: string }> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 768 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  const dataUrl = canvas.toDataURL('image/jpeg', 0.6);
  return { base64: dataUrl.slice(dataUrl.indexOf(',') + 1), mime: 'image/jpeg' };
}
