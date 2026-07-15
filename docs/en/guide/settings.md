# Preferences

The Preferences page consists of eight independent cards. Each card only modifies its corresponding configuration and does not affect other cards' settings. Modified configurations are saved to the application configuration file and read by the relevant features. Desktop widget-related settings are grouped under "Widget" separately.

## Personal Info

Personal info includes daily work hours, daily wage, and industry. Daily work hours and daily wage are used for the desktop widget's earnings timer; the industry serves as background information for AI organization.

Daily work hours are in hours, defaulting to 8. Daily wage is in RMB, defaulting to 200. Earnings are calculated using:

```text
Earnings per second = Daily wage ÷ (Daily work hours × 3600)
```

When daily work hours are less than or equal to 0, 8 hours is used for calculation. While the widget is running, earnings accumulate per second; accumulation stops when paused. After a local calendar date change, the current day's timer and earnings reset; cumulative statistics are retained.

The default industry is "Internet". It serves as context for AI requests like daily note organization, adjusting terminology and expression without changing raw facts, and does not trigger separate AI requests. Modifying personal information does not regenerate existing documents.

## Font & Display

Font & Display includes application font, theme mode, font size, and Markdown syntax highlighting.

**Application font** determines the font used by the interface and editor. When set to system font, the platform's default font is used; when other fonts are selected, the interface and editing area use that font on the next render. Font selection only affects display and does not rewrite document content.

**Theme mode** has three states: Follow System, Light, and Dark. When set to Follow System, the application switches based on the current OS theme; Light and Dark override the system theme. Theme switching only changes colors, backgrounds, and control appearances; it does not change wallpaper files or documents.

**Font size** is expressed as a percentage, defaulting to 100%, with an adjustable range of 80% to 140%. It affects the font size of the application interface and editor; the layout recalculates with the font size. It does not change text size in Markdown files.

**Markdown syntax highlighting** is enabled by default. When enabled, the editor only changes the color of Markdown symbols and syntax categories; when disabled, plain text is displayed. Regardless of the toggle state, characters, symbol shapes, saved text, and preview rendering results remain unchanged.

## Behavior & Startup

Behavior & Startup includes auto-start on boot, show updates, and API network logging.

**Auto-start on boot** launches SpringNote on system login. This option is only available on supported platforms; unsupported platforms show a platform restriction notice.

**Show updates** controls whether the application displays version update prompts. Disabling this does not prevent manual version and changelog viewing.

**Record API network logs** records AI-related network logs when enabled, useful for troubleshooting provider connections, request parameters, and returned errors. This is not equivalent to enabling AI and does not change request content. Logs may contain request metadata; be mindful of log file storage and sharing scope.

## Wallpaper

The Wallpaper card only controls the main application window's background. Modes include Default Background, Local Image, and Solid Color.

When selecting a local image, the image is copied to the wallpaper location in the data directory; the original file is not deleted. Fill modes include Stretch, Cover, and Center: Stretch changes the image aspect ratio, Cover maintains the aspect ratio and crops portions outside the window, and Center keeps the original size with the background color filling remaining areas.

Both image and solid color modes support opacity, blur, and mask intensity. The maximum blur value is 25. The mask adds a uniform color layer over the background. Opacity, blur, and mask only affect the main window's background display.

**Transparent control mode** reduces the occlusion of cards and the sidebar, allowing the wallpaper to show through controls. In this mode, you can also adjust control opacity, whether to keep card borders, and text color enhancement. When transparent control mode is off, these three linked options do not participate in display.

Restoring defaults resets the main window's wallpaper mode, image, color, opacity, blur, and control display to their default states.

## Tray

The Tray card includes two toggles: Show Tray Icon and Minimize to Tray on Close.

When "Show Tray Icon" is disabled, "Minimize to Tray on Close" is also disabled. Closing the main window and exiting the application are different behaviors: minimizing to tray keeps the process running and can be reopened from the tray; exiting the application terminates the background process.

The tray feature is only enabled on supported platforms; unsupported platforms show a platform restriction notice.

## Data Saving

The Data Saving card shows the current data directory and allows changing it via a folder picker. The data directory stores daily, weekly, and monthly notes, images, and application configuration; files selected from the home page are not currently copied here as attachments.

Changing the directory performs a data migration and updates the location used by the application. After a successful migration, subsequent records and images are written to the new directory; the old directory is not automatically used as the current directory after the switch. If errors occur during migration, the current configuration does not switch to an unconfirmed location.

## Prompts

The Prompts card contains home column and daily note organization prompts.

Home columns allow editing the titles and AI descriptions of the three columns. Titles are used for home page display; AI descriptions tell the AI what each column should focus on. When an AI description is empty, the corresponding title is used as the description. After saving, these affect future organization and do not reprocess existing home page overviews.

The daily note organization prompt controls how the AI merges the existing daily note with new input into the day's Markdown. The prompt can use built-in information such as the current date, existing daily note, new records, and industry. Modifications only affect future daily note organization and do not change already-saved daily notes.

## Memory Book Retrieval

The Memory Book Retrieval card controls the number and length of content the Memory Book tool reads and returns:

| Setting | Purpose | Default | Range |
| --- | --- | ---: | ---: |
| Max searches per round | Max searches allowed in a single answer round | 12 | 1–120 |
| Max characters per result | Max characters per record returned to the answer flow | 3600 | 80–10000 |
| Max consecutive daily notes | Max consecutive daily notes read in one request | 31 | 1–31 |
| Max keyword search results | Max records returned by keyword search | 12 | 1–200 |
| Context before match | Context characters preserved before the matched keyword | 1400 | 0–4000 |
| Context after match | Context characters preserved after the matched keyword | 2600 | 0–6000 |

These settings only affect the scale of content returned by Memory Book retrieval to the AI; they do not modify local Markdown files or change the notebook search return limit.
