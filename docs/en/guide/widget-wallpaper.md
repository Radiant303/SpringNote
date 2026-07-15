# Widget Wallpaper

Widget wallpaper only controls the background display of the desktop widget window and is completely independent from the main application wallpaper. It does not change the timer, earnings, buttons, or text content within the widget, nor does it affect the main window's background.

## Background Modes

The widget supports the following background modes:

- **Default background**: Uses the widget's default white background;
- **Solid color**: Uses a selected background color;
- **Local image**: Uses a selected image as the widget background.

Switching background modes only changes the widget window's display; it does not modify the timer state, position, or note content.

## Solid Color Background

In solid color mode, a background color can be selected. The color only affects the widget's background layer; the widget's text, timer buttons, and interactive states are determined by the widget theme.

## Image Background

After selecting a local image, the image is copied to the widget wallpaper location within the application data directory; the original file is not deleted. The widget reads the copied file for display; subsequent changes to the original file do not automatically update the saved widget wallpaper copy.

If the image path becomes invalid or the file cannot be read, the widget uses the available default background and does not delete timer records or modify the widget position.

## Opacity

Non-default backgrounds support opacity adjustment. This setting only changes the transparency of the background layer; the widget content layer remains readable. The default white background does not display this adjustment option.

Opacity changes do not alter the image file itself, nor do they affect the main application wallpaper opacity or transparent control settings.

## Restore Default

Restoring the default clears the widget wallpaper mode, color, image path, and opacity custom settings, returning the widget to its default background.

Restoring the default does not delete wallpaper files in the data directory, modify the main application wallpaper, or change the widget's display toggle, orb mode, position, timer state, or earnings statistics.
