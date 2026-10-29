export function createPointerOwner(clearManipulating) {
  let active;
  const matches = (item, id) => Boolean(active && active.item === item && active.id === id);
  function cancel() {
    const previous = active;
    // Clear ownership before releasing capture because lostpointercapture can re-enter.
    active = undefined;
    try {
      const element = previous?.item.element;
      if (element?.hasPointerCapture(previous.id)) element.releasePointerCapture(previous.id);
    } finally {
      clearManipulating();
    }
  }
  return {
    get active() { return active; },
    begin(gesture) {
      if (active) return false;
      active = gesture;
      try {
        gesture.item.element.setPointerCapture(gesture.id);
      } catch {
        cancel();
        return false;
      }
      return true;
    },
    matches,
    end(item, id) {
      if (!matches(item, id)) return false;
      cancel();
      return true;
    },
    cancel,
  };
}
