# New Conversation

Starting a new conversation clears the current Memory Book session and starts from an empty message context. The new conversation does not carry over questions, answers, thinking content, or read records from the previous conversation.

## Sending Messages

Every message you send carries its send time. The AI can perceive when each question was asked and how the conversation is spaced, and resolves relative times such as "today", "yesterday", or "this week" against the latest message's send time, without an extra lookup.

## Pasting Images

Press `Ctrl+V` (`Cmd+V` on macOS) in the Memory Book input box to paste images from the clipboard. Pasted images appear as thumbnails above the input box and are sent with the message. Pasting is currently supported only on Windows and macOS; on other platforms it is silently ignored and does not affect text input.

Pasting images requires the Memory Book model to have the "image" input mode enabled and its provider to use the OpenAI-compatible protocol. Otherwise, the notice "The selected memory model does not support image input." appears above the input box and the images are not added.

Pasted images are limited as follows:

- Up to 10 images per message;
- Each image must be 5MB or smaller, in png, jpg, jpeg, webp, or gif format.

Images are stored only in the `memory_images` folder of the local data directory and are never uploaded anywhere else; starting a new conversation clears them together with the session.

All images in the conversation share a total budget of 24MB. When a question is sent, images are counted per message starting from the newest; when a message would exceed the budget, its images are omitted as a whole and replaced with a placeholder in that message, so older images are omitted first.

## Input Modes

Input modes appear as tags in the input box. The "Mind Map" mode is currently supported.

### Mind Map Mode

After selecting "Mind Map", a blue tag appears in the input box. When you send a message, the tag asks the model to reply in `springtree` format, and the reply renders as a mind map in the bubble.

- The tag always stays visible in the input box and is treated as plain characters; pressing `Backspace` or `Delete` once removes the whole tag and turns the mode off.
- After sending, the mode tag stays in the conversation input box during a continuous conversation, so follow-up questions keep the same mode; deleting the tag restores plain-text answers.
- Quick action buttons (such as "view today's daily note") also use the mode tag currently in the input box when sending.

## Mind Map Interactions

Content returned by the model as a `springtree` code block renders as a mind map instead of a regular code block.

- **Pan**: drag on the canvas with the left mouse button, or drag on a touchscreen.
- **Zoom**: use the mouse wheel, or the zoom in/out buttons in the bottom-right corner; zoom is limited to 0.2×–3×.
- **Fit**: the fit button centers the canvas and zooms to show the whole map; after panning or zooming manually, it restores the initial view.
- **Fullscreen**: the fullscreen button opens the map in a fullscreen dialog with more room to view and interact; close it with the exit button or `Esc`.
- **Copy source**: the copy button in the map header copies the raw `springtree` text.

Node text is not selectable, so text selection cannot conflict with the pan gesture.

While the answer streams in, map nodes "grow" in one by one with a fade-and-scale animation; when a single update introduces more than 96 nodes at once, that batch appears directly without the animation, to keep the interface smooth.

The Memory Book page has no inline render limit — maps render in full from the parse result. Every map keeps at most 300 nodes when parsed; see "Markdown Rendering" for the inline render limit that applies in notes.

## Conversation Navigation

When the conversation has three or more rounds and the window is wide enough, a vertical rail of small dashes appears at the right edge of the chat area — one dash per round (one question); inactive dashes alternate between thick and thin by round number, making adjacent rounds easier to tell apart.

- **Current position**: the dash for the current round is longer and darker; the highlight moves as you scroll the conversation.
- **Click to jump**: clicking a dash scrolls straight to that question and highlights the dash right away.
- **Hover to expand**: hovering over the rail fades in a card listing each round's question text, so you can recognize a round before clicking; moving the mouse away collapses it back to dashes.
- **More than 9 rounds**: the rail shows only a 9-dash window around the current round and slides as you scroll; inside the hover card you can scroll through every round, with a slim scrollbar at the card's right edge.
- The navigation hides automatically when the window is too narrow.

## Context Isolation

A new conversation does not inherit search results or AI answer context formed during the previous conversation. Subsequent questions will re-determine which keyword search, date reading, or period reading tools to use.

Local daily, weekly, and monthly notes are not changed by starting a new conversation. A new conversation only affects the Memory Book session messages; it does not clear search indices, delete notes, or reset Memory Book retrieval settings.

## Session Cleanup

Starting a new conversation clears the currently saved Memory Book messages. The application currently does not have a separate history session list; once cleared, the previous conversation cannot be restored on the Memory Book page.

Local notes, search indices, provider configuration, thinking mode, and retrieval settings from before starting the new conversation are all preserved.

## Model State

Starting a new conversation does not re-select the Memory Book model, nor does it change the current thinking mode or provider configuration. When no model is available, local keyword search and record reading can still be performed in the new conversation; AI answer capability still depends on model availability.
