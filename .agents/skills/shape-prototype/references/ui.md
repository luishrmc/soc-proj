# Branch B: Multi-Variant UI Prototype

Render **3 to 5 structurally distinct UI variations** on a single route, switchable via `?variant=A|B|C` and a floating bottom navigation bar.

## Execution Steps

### 1. Prefer Embedding in the Existing Host Route

- **Sub-Shape A (Preferred)**: Mount variants directly inside the existing route or page so they sit alongside real navigation, real data density, and real project styling (Tailwind, shadcn, CSS modules).
- **Sub-Shape B (Fallback)**: Create a temporary `/prototype/<slug>` route using the project's existing router only when no host page exists.

### 2. Author Structurally Distinct Variants (`VariantA`, `VariantB`, `VariantC`)

Default to **3 variants** (maximum 5). Each variant must differ in **information hierarchy, layout structure, and primary interaction affordance** (e.g., dense table view vs. split master-detail pane vs. progressive disclosure cards), never merely color or copy tweaks.

### 3. Wire the Floating Variant Switcher

Render a compact, high-contrast fixed pill at the bottom-center of the viewport (`PrototypeSwitcher`):

- **Controls**: Previous arrow (`<-`), current variant label (`Variant B: Split Master-Detail`), and Next arrow (`->`).
- **URL & Keyboard Sync**: Clicking arrows or pressing Left/Right arrow keys (when no `<input>` or `<textarea>` is focused) updates `?variant=` in the URL so variants are reload-stable and shareable.
- **Production Guard**: Gate the switcher behind a development-environment check (`NODE_ENV !== 'production'`) and strip losing variants onto a `prototype/<slug>` branch once a winner is chosen.
