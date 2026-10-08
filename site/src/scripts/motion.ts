// Motion that follows the visitor: layers that move with the scroll and the pointer, and
// sections that come in as they are reached. None of it runs when no motion was asked for.

const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');

/**
 * Every `[data-parallax]` learns how far it is from the middle of the window, as `--scroll`:
 * 0 in the middle, 1 a window's height below it. Its `.layer`s move by that times their `--speed`.
 */
function followScroll() {
  const scenes = [...document.querySelectorAll<HTMLElement>('[data-parallax]')];
  const update = () => {
    if (reducedMotion.matches) return;
    for (const scene of scenes) {
      const rect = scene.getBoundingClientRect();
      if (rect.bottom < -innerHeight || rect.top > innerHeight * 2) continue;
      scene.style.setProperty('--scroll', ((rect.top + rect.height / 2 - innerHeight / 2) / innerHeight).toFixed(4));
    }
  };
  addEventListener('scroll', update, { passive: true });
  addEventListener('resize', update);
  update();
}

/** Every `[data-pointer]` learns where the pointer is over it, as `--mx` and `--my` from -1 to 1. */
function followPointer() {
  for (const scene of document.querySelectorAll<HTMLElement>('[data-pointer]')) {
    scene.addEventListener('pointermove', event => {
      if (reducedMotion.matches || event.pointerType !== 'mouse') return;
      const rect = scene.getBoundingClientRect();
      scene.style.setProperty('--mx', ((event.clientX - rect.left) / rect.width * 2 - 1).toFixed(3));
      scene.style.setProperty('--my', ((event.clientY - rect.top) / rect.height * 2 - 1).toFixed(3));
    });
    scene.addEventListener('pointerleave', () => {
      scene.style.setProperty('--mx', '0');
      scene.style.setProperty('--my', '0');
    });
  }
}

/** `[data-reveal]` comes in when it is reached, one after another within the same parent. */
function reveal() {
  let waiting = [...document.querySelectorAll<HTMLElement>('[data-reveal]')];
  for (const element of waiting) {
    const siblings = [...element.parentElement!.children].filter(child => child.hasAttribute('data-reveal'));
    element.style.setProperty('--order', String(siblings.indexOf(element)));
  }
  const update = () => {
    waiting = waiting.filter(element => {
      // Reached once its top is well inside the window; what was scrolled past counts too.
      if (element.getBoundingClientRect().top > innerHeight * 0.9) return true;
      element.classList.add('in');
      return false;
    });
    if (!waiting.length) removeEventListener('scroll', update);
  };
  addEventListener('scroll', update, { passive: true });
  addEventListener('resize', update);
  update();
}

export function startMotion() {
  followScroll();
  followPointer();
  reveal();
}
