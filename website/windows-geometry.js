const clamp = (value, min, max) => Math.max(min, Math.min(value, max));
export function clampFrame(frame, bounds) {
  const gap = Math.min(8, bounds.width / 8, bounds.height / 8);
  const width = clamp(frame.width, Math.min(180, bounds.width - gap * 2), bounds.width - gap * 2);
  const height = clamp(frame.height, Math.min(120, bounds.height - gap * 2), bounds.height - gap * 2);
  const top = bounds.top ?? 0;
  return { width, height, x: clamp(frame.x, gap, bounds.width - width - gap), y: clamp(frame.y, top + gap, top + bounds.height - height - gap) };
}
export function isDemoShortcut(event) {
  return event.metaKey && event.shiftKey && !event.altKey && !event.ctrlKey && !event.repeat && !event.isComposing && event.key.toLowerCase() === 'v' && !event.target?.closest?.('input,textarea,select,[contenteditable]:not([contenteditable="false"])');
}
export const nextDemoSlot = (count, limit) => count % limit;
export const canDrift = ({interacted, reduced, hidden, suspended}) => !interacted && !reduced && !hidden && !suspended;
