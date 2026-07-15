# New Conversation

Starting a new conversation clears the current Memory Book session and starts from an empty message context. The new conversation does not carry over questions, answers, thinking content, or read records from the previous conversation.

## Context Isolation

A new conversation does not inherit search results or AI answer context formed during the previous conversation. Subsequent questions will re-determine which keyword search, date reading, or period reading tools to use.

Local daily, weekly, and monthly notes are not changed by starting a new conversation. A new conversation only affects the Memory Book session messages; it does not clear search indices, delete notes, or reset Memory Book retrieval settings.

## Session Cleanup

Starting a new conversation clears the currently saved Memory Book messages. The application currently does not have a separate history session list; once cleared, the previous conversation cannot be restored on the Memory Book page.

Local notes, search indices, provider configuration, thinking mode, and retrieval settings from before starting the new conversation are all preserved.

## Model State

Starting a new conversation does not re-select the Memory Book model, nor does it change the current thinking mode or provider configuration. When no model is available, local keyword search and record reading can still be performed in the new conversation; AI answer capability still depends on model availability.
