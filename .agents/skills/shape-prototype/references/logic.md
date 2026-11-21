# Branch A: Logic & State Model Prototype

Build a single, self-contained HTML file that lets a developer or domain expert test-drive a state machine, reducer, or data model by clicking buttons.

## Execution Steps

### 1. State the Design Question at the Top

Render a visible one-paragraph banner at the top of the HTML page stating the exact state model and edge-case question under evaluation.

### 2. Isolate Pure Domain Logic in a Liftable Module

Place the state transitions inside a dedicated, pure `<script>` block with zero DOM references:

- **Pure Reducer**: `(state, action) => nextState`
- **Explicit State Machine**: Legal states, guarded transitions, and emitted events
- **Pure Domain Functions**: Transformations over plain data structures

Because the logic block contains zero `document` or UI bindings, the validated module can be lifted directly into the production codebase once the prototype settles the question.

### 3. Construct the Shareable Single-File HTML Shell

Use plain inline HTML, CSS, and vanilla JS (no build step, bundler, or server required) structured into four vertical panels using `GLOSSARY.md` domain terms:

1. **Question Banner**: Title and design question under test.
2. **Live State Inspector**: Formatted panel displaying current domain state fields and highlighting what changed on the last action.
3. **Free-Play Action Controls**: One button per domain action (disabling illegal transitions when testing state guards) so the user can probe arbitrary sequences.
4. **Tabbed Guided Walkthroughs**: 3 to 4 preset scenarios (Happy Path, Boundary Edge Case, Illegal Transition Attempt). Clicking a scenario tab resets to a deterministic initial state and presents ordered step buttons to walk through the case.
