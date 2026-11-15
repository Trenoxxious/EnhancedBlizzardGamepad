# Enhanced Blizzard Gamepad

By Noxxious.

On-screen gamepad keyboard for World of Warcraft: Forever (Interface 16001, Mainline 12.1.5 API).
Pops up whenever any text field gains focus while a gamepad is the active input: chat, auction house,
mail, professions, transmog, bag search, macros, other addons' edit boxes.

## Install

Copy the `EnhancedBlizzardGamepad` folder into `World of Warcraft/_classic_era_/Interface/AddOns/` (or whichever
product folder Forever uses on your install), then `/reload`.

## Controls (PlayStation names; Xbox equivalents in parentheses)

| Input | Action |
|---|---|
| D-pad | Move key selection (sticks stay with movement and camera; `/ebg sticks` captures them instead) |
| Cross (A) | Type selected key |
| Square (X) | Delete, hold to repeat |
| Triangle (Y) | Space |
| L2 (LT) | Shift. Press twice quickly for caps lock |
| R2 (RT) or Options (Menu) | Send / submit (R2 sends on release; hold R2 + D-pad left/right to switch chat tabs) |
| L1 / R1 (LB / RB) | Move text caret |
| L3 (LS click) | Toggle symbols page |
| R3 (RS click) | Delete previous word |
| Share (View) | Cycle chat channel: Say, Instance, Party, Raid, Guild, Yell, Whisper (only those available) |
| Circle (B) or Touchpad | Close keyboard and hand control back to the window behind it (text kept, except chat) |

Mouse clicks on keys also work, which is the fallback in combat.

## Slash commands

`/ebg` or `/ebgamepad`

- `show`, `hide`, `toggle` (toggle with no field focused opens chat)
- `auto on|off` auto popup on focus
- `pad on|off` require an active gamepad for auto popup
- `layout <id>` qwerty, azerty, qwertz, spanish, italian, portuguese, russian (default follows client locale)
- `scale 0.5-2`
- `skin dialog|classic|tooltip|metal|flat` panel art; `dialog` matches the native gamepad legend, `classic` uses the red UIPanelButton keys
- `bg <atlas>` swaps the panel background (default `auctionhouse-background-index`, scaled to cover and clipped inside the metal frame); `shade 0-1` sets the dark overlay strength
- `keyart <up> [down]` key face atlases (default `common-button-square-gray-up` / `-down`, sliced so wide keys keep their corners); `keyart off` for the built-in keys; `keypad 0-0.4` trims the atlas's empty margin
- `keybleed 0-12` pixels of the button art's shadow drawn outside each key (default 5); `keyglow 0-2` brightness of the selected key (default 1)
- `entrybox <base>` text field art from `<base>-left/-center/-right` (default `common-gray-button-entrybox`); `entrybox off` for the chat box art
- `glow editmode` draws the Edit Mode highlight box around the selected key, `glow <atlas>` any atlas, `glow off` plain gold key (default)
- `atlas` dumps the frame under the mouse (atlases, file IDs, fonts, nine-slice layouts) into a copyable window; `atlas PlayerFrame` by name; `atlas ui` dumps player/target frames, action bar, chat box and gamepad frames
- `check <names>` tells you whether atlas names exist on this build
- `glyphs` prints which controller atlas resolved for every pad button and which native templates are in use
- `prompts` toggles building the legend from Blizzard's own `GamepadPersistentInputLegendEntryTemplate` (default on)
- `enter` makes Send run a non-chat field's own Enter action again (off by default: Send keeps the text and closes the keyboard, which avoids running Blizzard code as addon code)
- `chatbox` toggles fading the real chat edit box while the keyboard is typing into it (default on, so the preview strip is the only visible input)
- `legend` toggles fading Blizzard's persistent gamepad legend while the keyboard is open (default on, since its L2/R2 hints conflict with Shift/Send)
- `probe [FrameName]` lists the mixin functions and fields on a frame; with no name it probes Blizzard's own gamepad InputIcon, which shows the API the native legend uses to pick button art
- `sounds`
- `status` prints gamepad and focus diagnostics

A key binding "EBG toggle" is also available under Key Bindings > AddOns.

## Focus rule (taint)

The addon never changes keyboard focus itself. On Forever, a focus change runs Blizzard's gamepad
binding manager; started from addon code it taints that manager for the session and Blizzard then
blocks `SetPreferredGamepadInteractTarget` ("blocked from an action only available to the
Blizzard UI"). So: Send in chat sends and clears but leaves chat open; Circle in chat empties the
message and passes the press through so Blizzard closes chat; outside chat, Send and Circle put
the keyboard away and leave the field focused. `/ebg show` reopens the keyboard on a field that
is still focused.

Bag and bank search are a second case: writing into that search box runs Blizzard's bag filter
as addon code and causes the same block. For those boxes the addon keeps the typed text itself
and sets the filter with `C_Container.SetItemSearch`; the real search box is never written to, so
it does not show the text. `/ebg bagsearch` turns this off.

## Group browser whisper

In the Looking For Group browser, with the gamepad cursor on a listing, hold R2 and press Cross
(A) to whisper whoever posted it. The keyboard opens on an addon-only composer already set to
that player; Send sends the whisper and closes the keyboard. Blizzard's chat box is not opened,
so this cannot cause the blocked-action error. While a listing is selected, R2 on its own does
nothing in that window. `/ebg lfg` turns the feature off.

## Channel tabs

When the target is a chat box the header shows a tab per channel, drawn with the key art and
wrapping onto extra rows when needed: Say, Instance, Party, Raid, Guild, Yell, each numbered
channel you have joined ("1. General"), "To Name" while whispering, "Reply Name" for the most
recent whisper received, and "Whisper". The active tab glows in its chat color, available tabs
show that color on the text, unavailable ones are dimmed. Share steps through the available
tabs. On "Whisper" the input strip reads "Whisper to:"; type a name and press Send to set the
target, then type the message. The input strip takes the active channel's color.

## Controller glyphs

Confirmed on build 16001: Blizzard's icon frame is `InputIconTextureFrameTemplate` (mixin
`InputIconTextureMixin`, `SetInputKey("PAD1")`) and the full icon-plus-text legend entry is
`GamepadPersistentInputLegendEntryTemplate` (mixin `InputPromptMixin`, `SetPromptInputIconKey`,
`SetPromptText`). The legend is built from those, so the art always matches the connected controller.
Fallback order if a template is missing: native icon frames, then atlas names, then text.

Blizzard identifies the controller through `C_GamePad.GetDeviceMappedState(id).labelStyle`
("Letters" for Xbox style, "Shapes" for PlayStation). The legend reads that, cross-checks it
against the atlas family the native `GamepadPersistentInputLegend` is drawing, and then resolves
each button to the client's own atlases (`Gamepad-PS-ButtonCrox-Normal`, `Gamepad-PS-TriggerL1-Normal`
and so on; the Cross typo is Blizzard's). Unknown names, such as Options/Share on PlayStation and
the whole Xbox family until confirmed, are probed from candidate lists and fall back to text labels.

## Skinning

`Skin.lua` builds the panel and preview box from Blizzard's own nine-slice layouts
(`NineSliceUtil.ApplyLayoutByName`) and the keys from `UIPanelButtonTemplate`, so the keyboard
inherits whatever art the Forever client ships and follows Blizzard's skin changes. Selection uses
the template's own locked highlight. Every path falls back to a flat backdrop if a template is missing.
Run `/ebg atlas ui`, copy the output, and the unit-frame atlases it lists can be dropped into the
presets in `Skin.lua` (or tried live with `/ebg glow <atlas>`).

## How it works

- `FocusTracker.lua` hooks OnEditFocusGained/Lost on every EditBox it can enumerate and polls
  `GetCurrentKeyBoardFocus()` every 0.1s as a catch-all. Forbidden frames are skipped.
- `Keyboard.lua` captures pad input with `EnableGamePadButton`, `EnableGamePadStick` and
  `SetPropagateKeyboardInput(false)` while shown. Those calls are protected in combat, so in combat
  the keyboard stays visible but mouse-only and re-arms on leaving combat.
- Text is written with `EditBox:Insert`, `SetText`, `SetCursorPosition`; backspace and caret moves
  are UTF-8 aware because cursor positions are byte offsets.
- Numeric boxes (`IsNumeric()`) get a numpad page.

## Languages

Layouts are plain data in `Layouts.lua`; adding one is a `define()` call with three letter rows.
Any script the client font can render works (Latin, Cyrillic, Greek are mapped for Shift).
Korean, Chinese and Japanese need the OS IME for composition, which addons cannot drive,
so those clients fall back to QWERTY.

## Things to verify on the live client

1. `/ebg status` with a pad connected: `active=true` and `glyphs` matching your controller.
2. Open chat with the pad, confirm the keyboard appears and the native bindings do not fire while typing.
3. AH search, mail body, profession search, transmog search: header names the screen, Start submits.
4. Enter combat with the keyboard open: combat badge appears, mouse still works, pad resumes after combat.
5. If `GAME_PAD_ACTIVE_CHANGED` never fires on this build, `pad off` forces auto popup regardless.
