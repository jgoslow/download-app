# Plan: Water Drop → Oscillating Circle SVG Animation

## Context

Standalone animation demo — a water drop shape that morphs into a loose oscillating blob when clicked. Intended as a reusable creative asset (could serve as a Basin loading indicator, recording state visual, or standalone demo).

## Output file

`docs/water-drop-animation.html` — self-contained HTML with inline SVG, CSS, and JS.

---

## Technical Approach

### SVG Structure

Single `<path id="drop">` inside an SVG with `viewBox="0 0 200 210"`. All states use the exact same path command signature:

```
M x y  C … C … C … C … Z   (4 cubic-bezier segments)
```

Same command count is required for CSS `d`-property morphing.

### Path States

**State 0 — Water drop** (sharp top point, round bottom):
```
M 100 12 C 130 12 166 58 166 108 C 166 150 138 188 100 188 C 62 188 34 150 34 108 C 34 58 70 12 100 12 Z
```

**State 1 — Resting circle** (slightly organic, used as oscillation base):
```
M 100 28 C 144 26 174 60 174 104 C 174 146 144 174 100 174 C 56 174 26 146 26 104 C 26 60 56 28 100 28 Z
```

**Oscillation keyframes** (4 frames, anchored to resting circle, bulges rotate around the shape):

| % | Description |
|---|---|
| 0% | Resting circle |
| 25% | Top-right quadrant swells outward |
| 50% | Resting circle (mirrored feel) |
| 75% | Bottom-left quadrant swells outward |
| 100% | Back to resting |

### Interaction Flow

1. **Idle**: drop shape is static (or with a very subtle 2s scale-pulse at 0.98–1.0)
2. **Click**: JS toggles `.activated` class on the `<path>`
3. **Morph**: CSS `transition: d 0.65s cubic-bezier(0.34, 1.56, 0.64, 1)` smoothly reshapes drop → circle with a slight elastic overshoot
4. **Oscillate**: on `transitionend`, JS adds `.oscillating` class which starts `animation: water-slosh 2.2s ease-in-out infinite`

### Visual Style

- Radial gradient fill: `#7dd3fc` (light center) → `#0ea5e9` (deep edge)
- Subtle inner highlight: a second small semi-transparent ellipse for a water sheen
- Background: dark (`#0f172a`) so the water blue pops
- Soft drop-shadow filter for depth
- "Click to activate" hint text below the shape, fades out after first click

### Browser Support

Uses CSS `d` property morphing — supported in Chrome 88+, Firefox 72+, Safari 13.1+. No polyfills needed for a modern demo.

---

## Implementation Steps

1. Create `docs/water-drop-animation.html`
2. Write SVG with `<defs>` block containing radial gradient + drop-shadow filter
3. Define the three path states as CSS custom properties or data attributes
4. Write CSS: idle state, `.activated` transition, `.oscillating` keyframes
5. Write JS: click handler, `transitionend` listener
6. Add "Click to activate" hint label that fades on first activation
7. Test visually in browser

---

## Verification

Open `docs/water-drop-animation.html` in a browser:
- [ ] Drop shape renders correctly on load
- [ ] Click triggers smooth morph → circle
- [ ] Circle oscillates continuously with a fluid, water-like rhythm
- [ ] No path "jump" (command count matches across all states)
- [ ] Gradient and shadow render as expected
