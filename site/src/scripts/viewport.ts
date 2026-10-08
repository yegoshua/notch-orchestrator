// The height of the window as the page should reckon with it. Mobile browsers change the real
// height while the page scrolls, as their toolbars slide away; what follows the scroll must not
// jump with it, so this is the small viewport, measured anew only when the width changes.

let height = 0, measuredAt = 0;

function measure() {
  const probe = document.createElement('div');
  probe.style.cssText = 'position: fixed; top: 0; height: 100svh; width: 0; visibility: hidden;';
  document.body.append(probe);
  // Browsers without the unit give the probe no height.
  height = probe.offsetHeight || innerHeight;
  measuredAt = innerWidth;
  probe.remove();
}

export function viewportHeight() {
  if (measuredAt !== innerWidth) measure();
  return height;
}
