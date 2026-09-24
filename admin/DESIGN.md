# Admin panel design

This file records how the panel looks and why, so that later changes keep the same look.

## The idea

The panel is a helpdesk for one question: **who needs help?** The busiest moment is a lab session, when a student cannot log in. So the first page is the student list with a large search box, and the chosen student opens on the right with their fixes (reset password, email login) at the top. There is no dashboard of big numbers, no card grid, and no sidebar. Server health is one sentence on that page and a plain document on the Server page.

It is built for daytime use in bright labs and offices, so light is the main theme. Dark mode follows the laptop's setting.

## Colour

Graphite on white, with a slight green tint in the neutrals. There are only three signal colours, and each has one job:

| Token | Light | Used for |
|---|---|---|
| `--pine` | `oklch(0.47 0.085 168)` | Anything you can do (primary buttons, links, focus) or have just done (success messages, the new-password box) |
| `--red` / `--red-ink` | `oklch(0.55 0.185 32)` / `oklch(0.47 0.17 32)` | Problems only: errors, stopped services, removing things |
| `--amber-ink` / `--amber-wash` | `oklch(0.48 0.1 65)` / `oklch(0.962 0.045 85)` | "Nearly": a disk at 80 to 89%, blocked lab computers |
| `--bg-2` | `oklch(0.977 0.006 165)` | The second layer: the side panel, the job output |

Colour appears only when something is actionable or wrong. A normal service simply says "Running", and a normal student shows only when they last signed in.

## Type

- **Atkinson Hyperlegible Next** for everything, and **Atkinson Hyperlegible Mono** for usernames, passwords and IP addresses. Both were designed by the Braille Institute so that look-alike characters (l, 1 and I; O and 0) stay distinct. That matters here, because passwords get read out loud across a lab.
- Both fonts are self-hosted in `public/assets/fonts/` under the SIL Open Font License (`OFL.txt`). The panel loads nothing from outside the server.
- Sizes are fixed (not fluid):

  | Element | Size and weight |
  |---|---|
  | Body text | 16px |
  | Page headings | 34px, bold |
  | Section headings | 20px |
  | Hints | 14px |
  | Password in the new-password box | 30px |

- Numbers use tabular figures.

## Shape and space

- Controls (buttons, inputs, list rows) have a 12px radius. Surfaces (the new-password box, the job output, notices) have 16px. Only the circular spinners, the progress meters and the small `/` key hint differ.
- Lists are separated by hairlines or space, never boxed.
- Buttons and inputs are 44 to 46px tall. The search box is 60px.
- More space goes above a heading than below it.

## Motion

Motion follows Emil Kowalski's rules: it only shows a change of state, and it stays under 300ms, using `cubic-bezier(0.23, 1, 0.32, 1)`.

| What happens | Motion |
|---|---|
| Opening a student with the mouse | The panel fades up 6px (220ms) |
| Opening a student with the keyboard | Instant, no animation |
| A disclosure opens | It fades down 4px (200ms) |
| A button is pressed | It scales to 0.97 |
| A message appears | It slides in from above; success messages leave by themselves after 7 seconds |

Hover effects only apply on devices that can hover. With reduced motion switched on, fades stay and all movement stops.

## Icons

Icons are [Phosphor Icons](https://phosphoricons.com), regular weight, MIT License. The path data is copied into `app/icons.php`. Use the same set for any new icon.

## Things to avoid

These were removed from the first version because they made it look generic:

- stat tiles with big numbers
- rounded cards around every section
- coloured pills on every status
- decorative status dots
- small uppercase labels above headings
- pop-up dialogs for routine confirmations
- a blue accent colour
- em dashes in the text

Dangerous actions are confirmed inline by typing the name (or `DELETE <number>`), not in a pop-up.

## How it was checked

- **Browser test:** `test/admin-panel-e2e.js` covers every main flow in a real browser.
- **Accessibility:** every page was checked with the axe-core scanner in light and dark mode and found no problems (WCAG 2.1 AA).
- **Design review:** a separate reviewer compared screenshots at 1440px and 390px against the rules above, using the Impeccable, Taste-skill and Emil Kowalski guidance.
