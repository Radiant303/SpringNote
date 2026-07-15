# Default Models

The Default Models page assigns a model to each of three independent purposes: Smart Generation, Edit Completion, and Memory Book. Each purpose can only have one current selection, but the three purposes can choose different providers and different models.

## Model Selector

Clicking the selection area for a purpose opens the model selector. Models are grouped by provider; the selector supports searching by model display name, model ID, or provider name.

"Not selected" is an explicit state in the selector. After making a selection, the application saves the provider-model association. Saving only a model name without a corresponding provider does not form a usable default model.

The model selection list only shows currently configured models. The Edit Completion list additionally filters by model type; only models flagged as supporting "Completion" appear.

## Smart Generation Model

The Smart Generation model is used for home page content organization, daily note merging, and AI generation of weekly and monthly notes. Once an available model is selected, the relevant features send requests to that model.

### With a Model Selected

The application checks whether the model's provider is enabled, whether the API Key exists, and whether the model is still in the provider's model list. If checks pass:

- The home page can perform Smart Generation;
- Daily notes can use AI merge;
- Weekly and monthly notes can request AI drafts;
- Models supporting image input can receive images pasted on the home page.

### Without a Model Selected

Home page text and saved images can still enter the local daily note processing flow, but no Smart Generation requests are made. Daily notes use local merge logic to generate savable content; weekly and monthly notes do not generate AI drafts.

## Edit Completion Model

The Edit Completion model is used for AI real-time completion in the notebook editor. The selector only provides models flagged as "Completion" in their model type, because real-time completion uses a dedicated completion request method.

### With a Model Selected

The editor requests this model when completion trigger conditions are met. After accepting the returned content, it is inserted at the current cursor position. Ignoring, canceling, timeouts, or request failures do not modify the original text or affect undo and save operations.

To be truly usable, the model must also meet the following conditions:

- Its provider is enabled;
- The provider's API Key is not empty;
- The provider uses the OpenAI-compatible protocol;
- The model still exists and retains the "Completion" type flag.

### Without a Model Selected

The editor does not initiate AI completion requests, but normal input, Markdown highlighting, undo, redo, save, and preview are all unaffected.

## Memory Book Model

The Memory Book model is used to generate AI answers based on keyword search results, date-specific records, weekly notes, and monthly notes. It is not responsible for local search itself; search and record reading work even without a model.

### With a Model Selected

The application first confirms that the model's provider is enabled, the API Key is not empty, and the model still exists. If checks pass, the Memory Book can generate answers based on search results and send requests according to the selected thinking level.

### Without a Model Selected

The Memory Book can still perform keyword search and read specified records, displaying matching results or Markdown content; but it will not generate full AI analysis, summaries, or follow-up answers.

## Model Invalid

After a default model selection is saved, if the provider is disabled, the API Key is cleared, the model is deleted, or the model type is removed, the configuration selection is not automatically replaced with another model, but the corresponding feature enters an unavailable state with the reason displayed.

Re-enabling the provider, restoring the API Key, recovering the model, or re-selecting an available model restores functionality. Changing the default model for one purpose does not affect the other two purposes.
