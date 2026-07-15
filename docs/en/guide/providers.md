# Providers

The Providers page manages AI service connections and model sources. The left side lists saved providers; the right side shows the current provider's connection information, enabled status, and model list. Provider search only matches provider names, not API addresses, model names, or keys.

## Provider List

The provider list displays the name, enabled status, and current model count. Clicking a list item switches the right side to the corresponding provider's detailed configuration. The selected state only changes the current view target and does not modify provider configuration.

The search box filters providers by name; the query is case-insensitive. When no match is found, an empty result is shown; clearing the search restores the full provider list. Search does not trigger network requests or modify provider data.

## Add Provider

When adding a provider, you can first select a built-in template. Templates pre-fill the provider name, protocol-corresponding default address, API path, and some example models; these can still be modified before saving. Current templates include OpenAI, OpenAI Responses, DeepSeek, Qwen DashScope, Kimi, OpenRouter, SiliconFlow, Ollama, Google, and Claude.

The add form includes:

- **Enabled**: Determines whether the provider can participate in AI requests after being added;
- **Name**: Local display name, also used for provider search;
- **API Key**: Service authentication info, displayed in hidden form;
- **Base URL**: The service's base address;
- **API Path**: The specific request path; some protocols like Gemini may not use this field.

Adding a provider only saves the local configuration; it does not automatically test the connection or set it as the default model for Smart Generation, Completion, or Memory Book.

## Connection Configuration

Provider details can modify the name, API Key, protocol, API Base URL, and API Path. The protocol determines the request format and some default addresses: OpenAI-compatible is used for chat or Responses requests; Gemini and Claude use their own request formats.

Modifying connection fields saves to the application configuration. A successful save does not guarantee actual service availability; actual availability also depends on the address, authentication, model ID, protocol, and server-side permissions.

## Enable & Disable

The provider enable toggle controls whether the provider participates in new AI requests. Disabling a provider does not delete connection information, model lists, or API Keys. After re-enabling, default models that meet other conditions can continue to be used.

If a default model belongs to a disabled provider, Smart Generation, Edit Completion, or Memory Book will show that the model is unavailable and will not automatically switch to another provider.

## Test Connection

Testing the connection initiates an actual connection test using the current provider and model configuration. The provider must have at least one model; if there are no models, the page first prompts you to add one.

The test result reflects whether the current service address, authentication info, protocol, and selected model can complete a request. A successful test does not mean all models support image input, tools, reasoning, or edit completion; these capabilities are determined by the model's capability flags and actual server-side support.

A failed test does not delete configuration, models, or notes. Common failure reasons include incorrect address, invalid API Key, provider model not authorized, network failure, protocol mismatch, and server-side errors.

## Fetch Models

Fetching models requests the model list from the provider and displays models that can be added or removed in a popup. The model list can be filtered by model name, model ID, or provider name, and is grouped by model ID prefix.

Fetched models are not automatically all added to local configuration. Models are written to the provider configuration only when the user adds them from the list; already-added models can be removed from the fetch results. If fetching fails, existing local models are not cleared.

Some providers do not provide a model list, or the API return format falls outside the supported range. In such cases, fetching models fails, but models can still be added manually.

## Add Model

Manually adding a model requires a model ID; the display name can be left blank, in which case the model ID is used as the display name. Adding a model only creates a local selection entry; it does not verify that the model actually exists or is callable.

Added models can have the following information edited:

- Display name;
- Model type: Chat, Completion;
- Input mode: Text, Image;
- Capabilities: Tools, Reasoning.

These flags affect the default model selector and feature availability. For example, the edit completion selector only shows models flagged as "Completion"; image input and thinking mode also check for corresponding capabilities. If flags are inconsistent with actual server-side capabilities, requests may still fail.

## Delete Model

Deleting a model removes it from the current provider's local model list. Features that had this model selected as their default become unselected or unavailable; they do not automatically switch to another model.

Deleting a model does not delete the server-side model or modify already-generated daily, weekly, monthly notes, or Memory Book messages.

## Delete Provider

Before deleting a provider, a confirmation popup is displayed. Confirming removes the provider's connection configuration, enabled status, and associated models; default model selections that depend on these models become invalid.

Deleting a provider only affects local configuration saved in SpringNote; it does not delete the server-side account, remote models, existing notes, or images. Deletion cannot be undone through the provider page; the provider must be re-added and reconfigured.
