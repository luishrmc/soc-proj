# Architecture Survey HTML Report Specification

Render the `arch-survey` output as a single self-contained HTML file in `${TMPDIR:-/tmp}/architecture-review-<timestamp>.html` using Tailwind CSS CDN and Mermaid v11 ESM.

## HTML Scaffold

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Architecture Survey: {{repo_name}}</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script type="module">
      import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
      mermaid.initialize({ startOnLoad: true, theme: "neutral", securityLevel: "loose" });
    </script>
    <style>
      .seam { stroke-dasharray: 4 4; }
      .leak { stroke: #dc2626; }
      .deep { background: linear-gradient(135deg, #0f172a, #1e293b); }
    </style>
  </head>
  <body class="bg-stone-50 text-slate-900 font-sans">
    <main class="max-w-5xl mx-auto px-6 py-12 space-y-12">
      <header>...</header>
      <section id="top-recommendation">...</section>
      <section id="candidates" class="space-y-10">...</section>
    </main>
  </body>
</html>
```

## Card Structure & Visual Patterns

Each candidate `<article>` must prioritize visual comparison over prose:

- **Title & Badges**: Action-oriented title ("Consolidate Order Intake Pipeline"), strength badge (`Strong` emerald, `Worth exploring` amber, `Speculative` slate), and dependency tag (`in-process`, `local-substitutable`, `ports & adapters`, `mock`).
- **Monospace File List**: Affected module paths (`font-mono text-sm`).
- **Two-Column Before / After Visual**: Mix Mermaid dependency/sequence graphs with Tailwind/SVG cross-sections (6 thin pass-through bands collapsing into 1 deep module band) or interface-to-implementation mass diagrams.
- **Problem & Solution**: One crisp sentence each using exact `arch-design` terms (*module*, *interface*, *depth*, *seam*, *adapter*, *leverage*, *locality*).
- **Wins List**: 2 to 4 bullets under 8 words each naming concrete leverage and locality gains (e.g., *"Locality: pricing invariants live in one module"*, *"Leverage: 1 seam replaces 4 wrapper mocks"*).
- **ADR Callout (Optional)**: Amber warning box if the candidate reopens an existing ADR in `docs/adr/`.
