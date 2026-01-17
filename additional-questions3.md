Here are some additional clarifying questions after reviewing the `PRD.md` file:

1.  **UI/UX Clarification**: The PRD mentions a "subtle blinking cursor" as a typing indicator and a "subtle spinner/dots" for processing. Could you clarify if both should be displayed simultaneously when new text is being drafted and then finalized? Or does the spinner show for a moment, and then the blinking cursor appears with the draft text?
2.  **Error Handling for Transcription**: The PRD states to "Silent skip" for transcription failures. In the case of a chunk failing, should this be logged for the user to see in the diagnostics, even if not shown in the main UI?
3.  **Session Naming**: The PRD says "Click to rename" for sessions. What should the UI for this look like? Should it be an editable text field directly in the sidebar, or should it open a modal dialog for renaming?
4.  **Multi-select copy**: The PRD mentions `Cmd+click` for multi-select copy. What is the expected behavior if a user `Shift+click`'s, which is a common pattern for selecting a range of items in a list? Should this also be supported?
5.  **Model Management**: The PRD mentions that there are no auto-updates for the model. If a user "clears the cache", will this re-download the *same* version of the model, or will it check for a new one at that point?
