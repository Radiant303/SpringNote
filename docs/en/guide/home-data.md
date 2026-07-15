# Data Overview

The values in the Data Overview come from records and statistics within the current data directory. They represent a summary of application state and do not modify daily, weekly, or monthly notes. Experience progress, hourly wage & earnings, and the activity heatmap use different statistical scopes.

## Experience Progress

Experience progress accumulates from successful home page organization events. A valid organization event occurs when a home page generation request succeeds and is recorded as a home page generation for that day. Simply opening the home page, saving content that does not trigger organization, or failed requests do not increase experience.

A maximum of 10 home page organizations are counted per day. Successful organizations beyond 10 in a single day can still update home page content but will not increase experience further, so repeated generation does not infinitely advance progress.

Total experience is divided into levels of 100 points each. Progress shows how much of the current level has been accumulated; reaching the next 100 points advances to the next level and resets progress from the new level's starting point. If statistics fail to load, the page uses available local state and does not block daily note saving.

## Hourly Wage & Earnings

Earnings come from the desktop widget's work timer. When the timer is running, earnings accumulate per second based on current settings; pausing stops accumulation.

Earnings are calculated as follows:

```text
Earnings per second = Daily wage ÷ (Daily work hours × 3600)
Current earnings = Earnings per second × Total seconds accumulated today
```

When daily work hours are less than or equal to 0, 8 hours is used as the default. Earnings accumulate per local calendar day; after midnight, the current day's timer and earnings reset. Historical cumulative earnings remain in the statistics.

The home page displays today's earnings and total accumulated earnings. Unsaved portions of the real-time timer are shown temporarily; failed statistics writes do not stop the timer. The application attempts to save unscheduled timer data on exit.

## Activity Heatmap

The activity heatmap shows activity over the last 140 days, with each date corresponding to an activity count. Activity counts come from statistical events such as successful home page organizations and edit completions, not simply from the existence of Markdown files.

The heatmap uses local date statistics. After midnight, new activity is attributed to the new date. Deleting history records does not automatically create new activity events, but refreshing statistics may update file counts and activity data.

| Daily Activity Count | Display Level |
| ---: | --- |
| 0 | No activity |
| 1–2 | Low |
| 3–4 | Medium |
| 5–7 | High |
| 8 or more | Highest |
