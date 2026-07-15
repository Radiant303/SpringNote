# Widget Settings

Widget settings control whether the desktop widget is displayed, its display form, and the basic behavior of the widget timer and position. The desktop widget is an independent window separate from the main application, currently supported on Windows and macOS; unsupported platforms show a platform restriction notice.

## Show Desktop Widget

"Show Desktop Widget" controls whether the widget window exists on the desktop:

- When enabled, the widget window can be displayed and receive operations such as dragging and timer control;
- When disabled, the widget window is hidden and no longer appears on the desktop;
- Hiding the widget does not automatically clear the current day's timer, nor does it pause or stop the timer.

Whether the widget is displayed is independent of whether the main application window is open. When the main application is minimized, closed, or in the tray, the widget can continue running according to its own state.

## Orb Mode

"Desktop Widget Orb Mode" controls the default display form of the widget:

- When enabled, the widget displays as an orb, occupying less desktop space;
- When disabled, the widget displays in expanded form showing timer and earnings information;
- The orb and expanded states can be toggled within the widget window; toggling does not reset the timer.

Orb mode is only configurable when the widget is enabled and the current platform supports desktop widgets. Switching display forms does not modify notes, statistics, or personal information.

## Mouse Operations

Mouse operations on the widget are consistent across Windows and macOS:

- **Left-click**: Toggles the work timer state. A running timer pauses; a paused or stopped timer starts. Clicking the orb does not open the main application.
- **Right-click**: Opens the SpringNote main window and switches to the Home page.
- **Left-click drag**: Moves the widget window. A movement threshold must be exceeded before a drag is registered; after dragging ends, the position is saved, and the timer state is not toggled.
- **Orb hover**: Moving the pointer into the orb's active area expands the widget; moving the pointer out of the active area collapses it back to an orb. While expanded, moving the pointer does not immediately collapse the widget just because it crosses the rectangular window boundary.

If the mouse button is pressed without actual movement, it is treated as a click. If a drag occurs, the mouse capture is cancelled by the system, or the operation is interrupted, the timer state is not accidentally toggled. Transparent areas of the orb are not considered valid click targets; clicks must land within the orb shape.

Right-click only opens the main window and does not change the timer state. After the main window opens, the widget retains its original running, paused, or stopped state.

## Work Timer

The widget displays the current timer state, today's accumulated work duration, and today's earnings. After starting, elapsed time accumulates gradually; after pausing or stopping, accumulation stops.

Hiding the widget, closing the main window, or switching orb mode does not automatically pause the timer. The timer state is maintained by the widget controller; when the widget is redisplayed, it continues showing the current state.

Timer data is written to statistics and synchronized to the hourly wage and earnings area on the home page. Short durations that are still running and not yet committed to statistics are shown temporarily on the current interface; the application attempts to save this timer data on exit.

## Earnings Calculation

Earnings are calculated based on the daily work hours and daily wage in Preferences:

```text
Earnings per second = Daily wage ÷ (Daily work hours × 3600)
Today's earnings = Earnings per second × Total work seconds today
```

When daily work hours are less than or equal to 0, 8 hours is used. Earnings accumulate by local calendar date; after midnight, the current day's timer and earnings reset, while historical cumulative statistics are retained.

Modifying daily work hours or daily wage only affects future timer calculations; it does not recalculate already-saved historical earnings or modify daily note content.

## Dragging & Position

The widget window can be dragged directly. After dragging, the position is saved to the configuration and restored on the next application start. Position saving uses delayed writes to avoid writing to the configuration file on every mouse movement.

On multi-monitor setups, the widget position is constrained within the visible work area. If the display count, resolution, or scaling changes and the original position is no longer visible, the widget is repositioned to a visible area to prevent it from appearing off-screen.

The orb and expanded states share the same position reference; switching states does not move the widget to a separate position.

## Platform & Error States

The widget feature is only available on Windows and macOS. On unsupported platforms, widget settings can still be displayed but the relevant controls are disabled.

If the widget window becomes temporarily unresponsive, note editing, AI requests, and local data saving in the main application are unaffected. When the window is redisplayed or reconnected, the current timer and display state are synchronized. If the position, display toggle, or orb mode becomes temporarily inconsistent with the page, reopening the widget or restarting the application re-reads the configuration.
