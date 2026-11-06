# Smart Chart project instructions

Ground decisions in the current code, tests, and available device evidence. Be direct about what you verified and what still needs checking.

## Keep tool guidance in sync

Treat user-facing tool guidance as part of the feature. Whenever a change adds, removes, renames, moves, or changes a tool function, update the affected on-screen helper in the same patch. This applies to commands, gestures, settings, defaults, supported chart layouts, feature gates, prerequisites, button availability, and recovery steps. A refactor that preserves user-facing behavior still requires a check that the existing guidance matches.

### Find the affected guidance

1. Trace the tool from its normal entry point through its available actions and what actually happens on tap, drag, write, or render. Check the chart type, active mode, settings, selection, and feature gates that affect the path.
2. Start with the quick explainer at the top of the tool screen. In the contextual editor helper implementation, the shared copy is in `iChart/Features/Editor/EditorCanvasMode.swift` under `activeToolInstruction`. `iChart/Features/Editor/EditorView.swift` owns the displayed row and state-specific prompts. Older branches may use different names. Search for the current helper before editing.
3. Check any other surface that teaches the changed action. This includes accessibility hints, menu or sheet instructions, empty and error states, the guided tour, and the in-app **How To** reference in `iChart/Features/Library/LibraryView.swift`. Update the surfaces that describe the affected behavior. Keep button names and gesture descriptions consistent across them.

### Write the helper

- Every user-facing editor tool screen needs a short, visible explainer at the top. State what the current tool can do and the next action the user should take. Use exact labels from the current UI, such as **Review & Render** or **End Repeat**.
- Tailor guidance when the available action depends on the chart layout, settings, selection, or a step in progress. For example, once a repeat starts, explain how to choose the last measure and finish it. Show commands only in the contexts where users can reach them.
- Remove instructions for retired or gated functions when those functions leave the shipped flow. When a command moves, update the entry path and the instructions at its destination.
- Keep the quick explainer concise and readable above the controls. Put longer walkthroughs in **How To**. The helper should wrap on narrow screens and at larger text sizes while leaving the controls reachable. Keep its layout stable during pen input and recognition feedback.

### Write & Render

- Handwritten repeat-sign and percent-style repeat ingestion is retired. Do not restore that recognition path or promise handwriting-to-repeat conversion. Direct repeat entry to **Tools > Repeats** and selected measures; preserve existing saved repeat notation and source ink. Ordinary barlines and handwritten ending brackets remain separate supported features.
- Check **Automatic** and **Manual Render with Preview** separately. Automatic guidance should explain writing in the highlighted lane, leaving space, pausing, and following review prompts when offered. Manual guidance should explain checking the previews and using the current render or review button.
- Check each supported chart layout. Describe the chord, barline, repeat, and ending gestures the current layout supports. For a Rhythm Section Sheet, distinguish drawing a barline to split an eligible open measure from editing an existing measure through **Measures**. Keep the distinction between staff handwriting in **Free Ink** and notation recognized by **Write & Render**.
- Keep no-read, wrong-read, repeat, and ending recovery instructions aligned with the actual prompt and available action. Distinguish the preview, the user's correction, the rendered result, and the saved chart. If a change affects what happens to the source ink, explain the effect at the action that consumes or clears it.

### Verify before closing a tool change

- Compare each affected helper with the actual controls and behavior. Exercise the normal entry point, the changed action, and any affected review or recovery path. Include each setting or layout where the instructions differ.
- For a UI change, check that the helper is visible on the tool screen, readable when it wraps, and consistent with the controls a user can reach. Verify that it does not push controls out of reach or make the writing canvas jump during input.
- Run the relevant editor, routing, or workflow tests. Update existing expectations where the instructions change and add focused coverage for regressions the existing tests would miss.
- In the handoff, identify the tool behavior and guidance updated together. Separate source review, automated tests, Simulator observation, and physical iPad results. A tool change is complete when the current behavior and the instructions agree.
