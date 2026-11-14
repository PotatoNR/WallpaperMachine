# Desktop widgets

Clocks, dates and the other widgets the app draws on the desktop, over whatever wallpaper is on
show. A widget
belongs to no wallpaper: applying another wallpaper, a playlist change or an automatic rule
leaves it where it is. They are set up in **Settings › Desktop Widgets**. People who update
from 1.10.0 or older are introduced to them once, in a window whose **Set Up Desktop Widgets**
opens that page ([feature introductions](updates.md#feature-introductions)).

## What the user sees

Unlike the other Settings pages, Desktop Widgets is not one scrolling column of rows: a widget
is arranged and styled by looking at it, and its forty-odd rows down one page kept every control a
long scroll from the picture it changed. Without a search the page is a **workspace**
(`WidgetsWorkspace`):

- a header with the section's name, **Ready-made** and **Add Widget**;
- a large **canvas** of the selected widget's display (of the main display while none is
  selected), as wide as the page leaves it, which grows with the window (see
  [the canvas](#the-canvas)); under it how to use it, and the **Center on the display** buttons
  (**Center Horizontally**, **Center Vertically**) for the selected widget;
- the **Layers** list under the canvas;
- an **inspector** beside the canvas, 340 points wide, naming the selected widget (what it says,
  its kind and display) above four tabs, **Content**, **Text**, **Style** and **Position**, and
  the rows of the tab chosen, which scroll on their own while the canvas and the layers stay put.
  A battery and a month calendar have no **Content** tab; a widget without the tab chosen last
  opens on its first. A wide control (a slider, a long menu, a field) sits under its row's title
  there.

When the page is narrower than 800 points the inspector goes under the canvas, before the
layers, and the canvas stays on show above them while they scroll. With no widget yet, the
inspector offers the ready-made widgets instead of the tabs; with none selected, it says so
(**No widget selected**) above them. A search shows the page as every
other page: the list, then the rows of every tab one under another (Position, Text, Style,
Content), with only those that match, and the Arrange picture as a row of Position.

**Ready-made** opens a popover of finished widgets, each drawn as the desktop will draw it over
the main display's wallpaper; a click adds it and opens it in the editor. Some are a group laid
out together, the widgets spaced by their real size on the main display
(`DesktopWidgetPreset`): **Big clock**, **Clock and date** (the date in spaced capitals under the
clock), **Neon clock**, **Clock face** (minute ticks on a glass disc), **World clocks** (New York,
London and Tokyo side by side, each labelled with its city, as badges), **Lunar date** (the
Chinese calendar), **Month calendar** (a badge at the top right), **Countdown**, **Greeting and
date**, **Gradient note** and **Battery and sun** (bottom left). They are ordinary widgets once
added: nothing remembers the preset. A group goes in front of the others, in its order; one that
would pass the limit is disabled, and adds nothing.

**Add Widget** is a menu of the kinds; the one chosen goes on the main display (the one with the
menu bar), a little below any widget already there, at the top of the list, and opens in the
editor. Up to 24 widgets can be added.

The **Layers** list is the widgets' layers, front first: where two widgets overlap on the
desktop, the one higher in the list covers the other (with two or more widgets, the list says
so). Each row shows a drag handle, the widget's words now (the first line of a text, the
month of a calendar), its kind and its display (and **Hidden** for one switched off), and two
buttons: the eye shows or hides it on the desktop, and the trash removes it after asking once more
in place (**Cancel** or **Remove**), since a removal cannot be undone; the editor then moves to
the next widget. A click picks the widget the inspector edits, and the selected row is
highlighted. Dragging a row's handle onto another row puts it in that row's place; a drop made
from an order that has changed since is refused. The row's context menu has **Show on the
desktop** or **Hide on the desktop**, **Duplicate** (a copy just in front of it, a little lower on
the display, opened in the editor), **Bring to Front**, **Bring Forward**, **Send Backward**,
**Send to Back** and **Remove**; VoiceOver offers Bring Forward and Send Backward as actions of
the row. In the search results, the first group of the editor names the widget it edits on its
title line.

### The canvas

The canvas shows the display's wallpaper ([its backdrop](#the-previews-backdrop)) and every widget
shown there, stacked as on the desktop. A click on a widget selects it; dragging it moves it,
snapping to guides ([snapping](#snapping-and-guides)). The selected widget is outlined above every
layer, so it can be found under another one, with:

- a square **handle at each corner**: dragging one resizes the widget about its middle, by the
  pointer's distance from the middle over its distance when the drag began (10 to 320 points);
- a round **knob** above it (below it when the widget is at the top of the display) on a short
  stem: dragging it turns the widget about its middle, settling on every 15° within 4° of one
  unless Command is held; a double click turns it upright.

While a handle moves, its size ("128 pt") or turn ("15°") shows under the widget; the change is
saved when it is let go, as a move is. Once the canvas has been clicked, the arrow keys move the
selected widget one point of the display, ten with Shift.

A click on the wallpaper around the widgets, or Escape on the canvas, **selects nothing**, to see
the widgets as the desktop will show them: no outline or handles, no highlighted layer, and no
hidden widget (one is drawn, faded, only while it is selected). The canvas stays on the display it
showed, the arrow keys move nothing, and the inspector says no widget is selected above the
ready-made widgets. Clicking a widget on the canvas or in the layers, or adding one, selects it
again. The search results keep editing the widget chosen last. A widget's context menu on the canvas
has **Hide on the desktop** or **Show on the desktop**, **Duplicate**, **Bring to Front** and
**Send to Back**. The canvas is hidden from VoiceOver: the rows of the Position and Text tabs do
the same from the keyboard.

| Kind | Shows | Changes |
| --- | --- | --- |
| **Clock** | The time, of this Mac's time zone or another city's, after an optional label | Each minute, or each second with seconds |
| **Date** | The date in one of eight styles, in the region's calendar or another one, of this Mac's time zone or another city's, after an optional label | At midnight |
| **Text** | Words the person wrote, on one line or several | Never |
| **Countdown** | "12 days until Launch", "Launch is today", "3 days since Launch"; without an event name, the day itself names it | At midnight |
| **Greeting** | Good morning (from 5), afternoon (12), evening (18) or night (22), with a name if given | At those hours |
| **Battery** | "Battery 82%", or "Charging 82%" while it charges; "No battery" on a Mac without one | When the battery's notification says the reading changed |
| **Sunrise and sunset** | The next sunrise or sunset, or both of today's | At each of them and at midnight |
| **Analog clock** | A clock face with hour marks and hands, a second hand if asked | Each minute, or each second with seconds |
| **Month calendar** | This month's name, the weekdays and the days in a grid, today in bold and underlined; weeks start on the region's first weekday | At midnight |

The tabs of the inspector, and the groups they hold:

- **Position** (the Position group): **Show on the desktop**; **Display** (**Main display**,
  which follows the menu bar, **All displays**, or one display by name; a display that is not
  connected stays in the menu as "*name* (not connected)" and the widget comes back when it
  does); in the search results only, **Arrange** (the canvas as a row, 480 × 270 points at most)
  and **Center on the display**, which the workspace shows by the canvas; **Horizontal position**
  and **Vertical position**, the same place in whole percent from the left and the top edge, for
  the keyboard and VoiceOver; **Alignment** (**Left**, **Center**, **Right**), the edge of the
  text the position holds, so a clock aligned left does not move its left edge when "9:59"
  becomes "10:00"; **Rotation**, −180° to 180°, turning the whole widget about its middle; the
  frame grows to the turned box, which then sits where an unturned widget would. A hidden
  selected widget is drawn faded on the canvas so it can still be arranged. **Center on the
  display** (**Center Horizontally**, **Center Vertically**) puts the middle of what the widget shows on the
  display's centre line, whichever edge its alignment holds, each button disabled while that is
  already so.
- **Text** (the Look group): **Size** (10 to 320 points; a clock face is one and a half times its
  size across);
  **Typeface**, the system font's four designs (**Standard**, **Rounded**, **Serif**,
  **Monospaced**) or any font family installed on this Mac, listed by name (read once a launch; a
  family since removed is offered as "*name* (not installed)" and draws in the system font); for
  a clock face it is the font of its numbers; **Weight** (100 to 900 in steps of 100, the nearest
  face the family has); **Italic** (a font without an italic is slanted instead); **Letter
  spacing** (−10 to 50 % of the size) and **Letter case** (**As written**, **Uppercase**,
  **Lowercase**, by the language's rules), not for the clock face; **Line height** (70 to 200 %)
  for a text and a clock. Digits keep one width in every font that has tabular figures, so a clock
  does not shift as it counts. The lines of a text line up on the edge chosen in **Alignment**.
- **Style**: first **Style**, the finished looks (**Soft shadow**, a new widget's; **Plain**;
  **Neon**; **Outlined**; **Badge**; **Glass**; **Sunset**; **Long shadow**), each a swatch of the
  selected widget's own words in that look over the wallpaper, a click setting the colours and
  effects below in one go, starting from a new widget's, and never the font, the size or the
  place; then the Colors and Effects groups.
- **Colors**: **Color**; **Accent color**, the second hand of a clock face and today in a month
  calendar (the colour until one is chosen; **Use Text Color** goes back to it); **Gradient**, which
  fades the colour into a **Second color** along a **Gradient direction** (0° to 359° clockwise from
  upwards; 180° runs from the top down) across the whole widget, accent included; and **Opacity**
  (10 to 100 %), which applies to the whole drawing, effects and background included.
- **Effects**: **Outline** (0 to 15 % of the size, 0 for none) in an **Outline color**, drawn
  outside the letters (round-joined) and around every line of a clock face; **Glow** (0 to 50 %,
  0 for none) in a **Glow color**; **Shadow**, with **Shadow color**, **Shadow opacity** (10 to
  100 %, 45 for a new widget), **Shadow blur** and **Shadow distance** (0 to 50 % of the size; 6 and
  2) and **Shadow direction** (clockwise from upwards; 180° falls straight down); **Background**
  (**Off**, **Rectangle**, **Rounded rectangle**, **Capsule**: a circle behind a clock face) with
  **Background color**, **Background opacity** and **Background padding** (0 to 100 % of the size);
  **Reset effects** puts gradient, outline, glow, shadow and background back to a new widget's.
  The rows that only matter once a choice is made (the second colour, the shadow's details, the
  background's) show only then, and search finds them only then.
- **Content** (the Format group), by kind:
  - a clock: **Time format** (**Follow system**, **12-hour**, **24-hour**), **Layout** (**One
    line**, or **Stacked**: the hour over the minutes, over the seconds and AM or PM, each in the
    locale's digits, the label on a line above), **Leading zero** ("09:41"; a region that writes
    two digits keeps them), **Show AM/PM** (off drops the period and the space beside it, wherever
    the region writes it), **Show seconds**, **Time zone** and **Label**;
  - a date: **Date format**, whose menu writes each style out for today (weekday, month and day;
    month, day and year; the short form; numbers only; the weekday alone; month and year; the
    week of the year, numbered as the region numbers weeks; the day of the year), **Calendar**
    (**Follow system**, or the Chinese, Islamic (Umm al-Qura), Hebrew, Persian, Buddhist,
    Japanese or Indian calendar, each named in the panel's language and written in that
    calendar's own words: "九月三十" in the Chinese calendar), **Time zone** and **Label**;
  - an analog clock: **Dial** (**Hands only**, **Hour marks**, **Minute ticks**, **Numbers**,
    **12, 3, 6 and 9**), **Show ring**, **Show seconds** and **Time zone**;
  - a text: **Text** (Option-Return starts a new line); a countdown: **Event** and **Count down
    to**, a date picker; a greeting: **Your name**;
  - sunrise and sunset: **Sun times** (**Next sunrise or sunset**, **Today’s sunrise and
    sunset**) and **Time format**. The times are those the automatic wallpapers plan with
    (Settings › Displays › Sunrise and sunset): worked out from the coordinates typed or found
    there, or the two clock times fixed there. Without a place it says so; on a polar day or
    night it says there is none today.
  - a battery and a month calendar have no format of their own.

  **Time zone** offers this Mac's own and fifty cities, one for each offset people live at, by
  the city's name in the panel's language and its offset from GMT now. Choosing a city for a
  clock or a date without a label labels it with the city; a label of one's own stays. The
  label, a text, an event or a name keeps at most 500 characters.
Every change shows on the desktop at once, a colour while it is being picked in the colour
panel included; none of these controls waits for the renderer or for a wallpaper being applied.
The words follow the Mac's language and region formats (System Settings › General › Language &
Region) and its time zone, as the menu bar clock does, and change with them. The phrases of their
own (a countdown, a greeting, the battery, the sun, "Week" and "Day") are in the language the app
was launched in.

## How it is drawn

`DesktopWidgetController` (`App/Services/Desktop/`), started by `AppDelegate`, puts one
`MWEDesktopWidgetWindow` (`DesktopWidgetWindow`) on each display a shown widget belongs on, and
stacks the windows in the layers' order: they share one window level, so each is ordered in front
of the one behind it, only when a window is added or the order changes. The
window is transparent and only as large as its text and shadow, one level above the wallpaper
windows (the [coverage probes'](../architecture.md#desktop-wallpaper-windows-and-private-api-handling)
level) and below Finder's desktop icons, on every Space, ignoring the mouse and never hidden with
the app. Its class is not a wallpaper window class, so occlusion tracking, the window audit and the
desktop-picture posters never look at it. Being transparent, and never as tall as a display's
working area even at the largest size, it never makes a display count as covered. A click on a
widget reaches the desktop beneath it.

`DesktopWidgetRendering` holds what both the desktop and the panel's canvas, swatches and
ready-made cards draw: the
words (a Unicode date template the locale arranges, through cached `DateFormatter`s; a clock's
leading zero, missing AM/PM and stacked lines rewrite the locale's own pattern, quoted words
kept), the month grid (right-aligned tab stops, one per weekday), the clock face (where each hand
points, its marks and numbers), the font, the `Look` (opacity, turn, gradient, outline, glow,
shadow, background, every length in points at the scale drawn) and the frame.
`DesktopWidgetView` draws text from the top of its frame, or the face, in transparency layers: the
letters or the face are filled, a gradient replaces their colour where they are (`sourceIn`), the
outline goes behind them (`destinationOver`), that group casts the glow (drawn twice, so it reads
as light) and then the shadow, the plate sits under everything without a shadow, and the opacity
applies to the whole. Crossing hands neither darken nor shadow each other, and an outline or a
gradient never shows through the letters. All of it is drawn only when the words or the look
change, as before; no effect animates. The padding around the content is the reach of its shadow, glow and outline, or the
background's padding, whichever is larger. The position names the
content's chosen edge and its vertical centre as fractions of the display; the frame is then
moved, never shrunk, to lie on the display, and is cut only when the content is wider than the
display or taller than 60 % of it, so even a long text never covers a display's working area.

The windows cost nothing between changes of their words:

- Without widgets the controller keeps no window and no timer and only listens for the store's
  change.
- With widgets it redraws when what they show changes (the **Changes** column above), each in
  its own time zone, from one one-shot timer for all of them. Texts and batteries alone schedule
  no timer. A widget's view redraws only when what it draws changed, and a window moves only
  when its frame did.
- The battery's IOKit notification (`SystemBatteryLevel`) is registered only while a battery
  widget is placed, and redraws only when the reading changed; nothing polls it.
- A change of the sunrise and sunset settings (`WallpaperAutomationStore.didChangeNotification`)
  reads them again from the preferences and redraws.
- While none of the widget windows can be seen (windows cover them, the displays sleep, the
  screen is locked) no timer is scheduled; the occlusion change of a widget window brings them up
  to date and schedules the next change again.
- A wake, a change of the clock, the time zone, the region format or the day redraws at once. A
  screen change moves the windows and touches only the ones whose frame changed, so an XDR
  display's stream of EDR headroom changes touches none.

## Snapping and guides

While a widget is dragged on the canvas, the display's two centre lines show faintly dashed, so
the centre can be found before the widget gets there. Within about 6 of the picture's points of a
line, the widget snaps onto it (`DesktopWidgetSnapping`), and a solid guide in the accent colour
(over a dark hairline, readable on any wallpaper) is drawn along each line it lies on:

- the display's centre lines, with the widget's middle;
- the lines a third of the way across and down, with its middle (dashed guide);
- a margin of 4 % of the display's shorter side in from each edge, with the edge facing it
  (dashed guide);
- every other widget shown on that display: its left, middle and right, and its top, middle and
  bottom, with the dragged widget's; that guide runs between the two widgets.

The nearest line on each axis wins, so a widget can sit on a vertical and a horizontal line at
once. Holding **Command** while dragging places the widget freely. The lines are worked out on the
display at the widgets' real size, not on the scaled picture, whose text is laid out at another
size, so a widget snapped to the centre is centred on the desktop to the point.

## Storage

The widgets are a JSON array in the app's preferences (`WallpaperMachine.desktopWidgets`,
`DesktopWidgetStore`), in the layers' order, front first. Each field has a default, so a widget saved by another version keeps what
it carries; a saved list with a value no control could choose (out of range, an unreadable
colour, a repeated id) is not read, and the log says so. The panel's store writes the list and
posts `DesktopWidgetStore.didChangeNotification`; the controller reads the list again from the
preferences.

A [backup](backup-restore.md) carries the widgets and refuses a list with such a value.
**Reset all settings** keeps them, as it keeps playlists, presets and display layouts.

## The preview's backdrop

The canvas shows the wallpaper as the display draws it, not the author's preview
image, which often has another shape, crop and resolution. When the row appears, or the
display's wallpaper or its files change, the page asks the wallpaper's own surface for one frame
through the poster pipeline ([when a poster is taken](desktop-picture.md#when-a-poster-is-taken)):
a Metal readback for a scene, a snapshot for a web page, the player's frame for a video. The
frame has the display's aspect and the wallpaper's placement, scaling and properties; it is
scaled to at most 2048 pixels on its longer edge (sharp on a Retina canvas up to about 1,000
points wide) and only that copy is kept
(`DesktopWallpaperFrames`, wired as `BridgeStore.wallpaperFrame`).

Many wallpapers open with an intro or fade in from black, so the first frame is shown at once
and replaced by a **settled** one once the wallpaper has played a moment:

- `WallpaperSettleClock` counts, per display, how long the wallpaper has played where it can be
  seen: time paused, covered, asleep or suspended by a rule does not count, and a new wallpaper,
  a new window or new files start the count again. The app reports what each display shows after
  every engine snapshot, host pass and presentation change. A wallpaper has settled after the
  desktop picture's settle window, 15 s (`DesktopWallpaperSync.settleCaptureDelays`).
- The wallpaper is asked presenting or not: the panel's own window usually covers the display,
  and a paused surface answers with the frame it holds without playing on, which is past the
  intro when it had played long enough before it stopped. A wallpaper that has not settled
  gives that frame as its first picture.
- A frame that is black or one flat colour all over (sampled on a 32 × 32 grid) is never shown.
- The last settled frame of each display is kept in memory with its `DesktopPosterLook`, so a
  wallpaper replaying its intro under the same look still shows it; a new look drops it.
- Without a frame of its own, the desktop picture sync's poster stands in when it has settled
  (`DesktopWallpaperSync.settledPoster(display:)`: taken while presenting after the settle
  captures of the wallpaper's start, or given back as settled).
- With nothing settled, the first frame shows, and without one (or a blank one) the still with
  the note "Showing the wallpaper's preview image until it has played for a moment." under the
  picture. A wallpaper that plays is asked again after the rest of the settle window. One that
  does not play, such as one paused because the panel covers the desktop (**When the desktop is
  covered** › **Pause**), does not move on, so it is asked again when it next starts or stops
  playing where it can be seen (`WallpaperSettleClock.nextChange`, which sleeps only while a
  waited display plays), and settles once it has played the window. Nothing renders a covered
  wallpaper to settle it. The wait is the row's task and ends with the row.
- The request carries its own `panel-preview:` context, so the desktop picture sync never takes
  the frame as a poster. When the sync is waiting for a frame from that surface, the page asks
  nothing and takes the sync's frame: a renderer answers piled-up requests with one frame
  carrying the newest request's context, and asking would cost the sync its frame.
- No timer runs while the row is not shown and no second renderer runs; the frame is a still.

## Limits

- Only the live desktop shows widgets. The lock screen and the screen saver show only the
  wallpaper (macOS draws its own clock there), and so do the still pictures the app writes as
  the macOS desktop picture, which Mission Control and a quit show.
- Widgets cannot be clicked or dragged on the desktop itself; they are arranged in Settings.
- The effects are still: nothing pulses, shakes, scrolls or blinks (as Wallpaper Engine's text
  layers can), because a widget is drawn only when its words change and costs nothing between.
  There is no blur of the wallpaper behind a background either: it would make the window server
  blur every frame of a moving wallpaper.
- The kinds are the app's own: lifting a layer out of a scene wallpaper (such as another
  wallpaper's clock) is a different feature this one does not do. Weather, calendar events,
  system load and Now Playing are not offered: they would need a network service, a permission
  prompt, polling or a private framework.
- The battery line in the panel's preview uses the level the panel last read and does not tell
  charging apart; the desktop does.
- A display mirrored to another shows what that one shows.

## Code and verification

- `App/Services/Desktop/`: `DesktopWidget` (the record and its validation),
  `DesktopWidgetStore`, `DesktopWidgetRendering`, `DesktopWidgetController`,
  `DesktopWidgetWindow`, and `DesktopWallpaperFrames` and `WallpaperSettleClock` (the preview's
  backdrop).
- `App/Services/Desktop/DesktopWidgetPreset.swift`: the ready-made widgets and their layout.
- `App/Views/ControlPanel/`: `Settings/Sections/WidgetsWorkspace.swift` (the workspace, the
  ready-made cards and the style swatches), `WidgetsSettingsSection.swift` (the searchable rows,
  the search results' page and `WidgetEditor`, the rows by tab) and `DesktopWidgetPreview.swift`
  (the canvas and its handles), the page model `Settings/DesktopWidgetsSettingsModel.swift` (the
  selection, the tab, drags, resizing and turning), the snapping
  `Settings/DesktopWidgetSnapping.swift`, `SettingsPages` (which shows the workspace without a
  search) and the typed actions in `Model/PanelController+DesktopWidgets.swift`.
- Tests: `Tests/Unit/Desktop/DesktopWidgetTests.swift` (each kind's words, a clock's leading
  zero, AM/PM and stacked lines, the letters' case, spacing and slant, installed and missing font
  families, the room effects take and a turned frame, the styles and resetting the effects, the
  clock face, the month grid, other calendars and time zones, frames and the height limit, the
  next change, storage and backup validation, the layers' order, moving and duplicating),
  `DesktopWidgetControllerTests.swift` (windows per display, stacking in the layers' order,
  timing, occlusion, wake and screen changes, the battery's notification and the sunrise and
  sunset settings, the window's level and class) and `Tests/Unit/Panel/WidgetsSettingsTests.swift`
  (actions, layers and the preview's stacking, snapping a drag and the Center buttons, resizing
  and turning by the handles and nudging, the ready-made widgets' layout and limit, the
  inspector's tabs, the
  Display, Date format, Time zone and Calendar menus, the rows each kind offers and those waiting
  on another choice, the preview's wallpaper frame, search and layout of the workspace in a
  narrow, a middle and a wide column in every tab); `testSnapshotsOnRequest` writes offscreen
  renders of the workspace to the folder in `WALLPAPER_MACHINE_WIDGET_SNAPSHOTS` (pass it as
  `TEST_RUNNER_WALLPAPER_MACHINE_WIDGET_SNAPSHOTS`) for a person to look at; `Tests/Unit/Panel/DesktopWidgetSnappingTests.swift` the snap lines, the pull and the
  guides.
  `DesktopWallpaperFramesTests.swift` covers asking a settled wallpaper once and scaling, waiting
  for the sync's own frame, not asking during an intro, the frame kept per look, blank frames and
  the poster fallback; `WallpaperSettleClockTests.swift` the settle count.
- The unit tests never put a widget window on screen. What a widget looks like on a real
  desktop (the clock face, the month grid and every effect included), over each kind of wallpaper and across
  Spaces, is checked by hand.
