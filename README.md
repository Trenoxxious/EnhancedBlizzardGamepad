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
| L3 (LS click) | Toggle symbols page (the ?123 / ABC / Àé keys switch pages too; selection stays on the key pressed, and every typing page is the same size) |
| R3 (RS click) | Delete previous word |
| Share (View) | Cycle chat channel: Say, Instance, Party, Raid, Guild, Yell, Whisper (only those available) |
| Circle (B) or Touchpad | Close keyboard and hand control back to the window behind it (text kept, except chat) |

Mouse clicks on keys also work, which is the fallback in combat.

## Settings window

EBG's own window holds the everyday settings: enable, automatic opening, gamepad-only, sounds,
layout, style, scale, background shade, left-stick selection, navigation pointer, the chat
settings (close after Send, hide the chat input, chat copy, right-stick scroll, fade the chat
window, group finder whisper), Blizzard's legend and prompts, and the auction house settings.
Art overrides and diagnostics stay as slash commands.

Open it from:
- the small gear in the keyboard's top right corner (click it, or D-pad up from the top row's
  last key, Delete, then Cross/A; "Settings" shows beside the gear while it is selected),
- the gear key beside "Close auction house" in the gamepad auction browser (left from Close),
- `/ebg` with nothing after it, or `/ebg options`.

In the window: D-pad up/down moves, left/right changes the value (left turns a toggle off,
right turns it on), Cross (A) flips a toggle or steps a list, L1/R1 jump between sections, and
Circle (B), Options (Menu) or Escape closes it. The line under the list explains the selected
setting. The mouse works too (click a row; right-click steps a list backwards; wheel scrolls).

The window holds the pad while it is open: the keyboard and the auction browser let go of it
when it opens and take it back when it closes. It closes when combat starts, because pad capture
cannot change in combat. It is deliberately not a page in Esc > Options > AddOns: those pages are
not reachable with the D-pad, and on Forever the game's settings list carried taint from addon
rows into other pages (the Social page had `IsUserOAuthed` blocked). Every control reads and
writes through its setting's get/set in `Options.lua`, so it shows the value the code actually
uses (several settings are stored as "unset means on") and applies changes at once.

## Slash commands

`/ebg` or `/ebgamepad` (no command opens the settings window; `help` lists the commands)

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
- `ah` opens the gamepad auction browser while visiting an auctioneer; `ah auto` toggles automatic opening with a gamepad
- `enter` explains the retired Enter-handler option. Native Enter handlers are never executed by EBG; Done keeps text and closes the keyboard
- `chatbox` toggles fading the real chat edit box while the keyboard is typing into it (default on, so the preview strip is the only visible input)
- `closeonsend [on|off]` Send in chat also closes chat and the keyboard (default on; see Focus rule below)
- `legend` toggles fading Blizzard's persistent gamepad legend while the keyboard is open (default on, since its L2/R2 hints conflict with Shift/Send)
- `probe [FrameName]` lists the mixin functions and fields on a frame; with no name it probes Blizzard's own gamepad InputIcon, which shows the API the native legend uses to pick button art
- `sounds`
- `status` prints gamepad and focus diagnostics

A key binding "EBG toggle" is also available under Key Bindings > AddOns.

## Focus rule (taint)

The addon never changes keyboard focus itself. On Forever, a focus change runs Blizzard's gamepad
binding manager; started from addon code it taints that manager for the session and Blizzard then
blocks `SetPreferredGamepadInteractTarget` ("blocked from an action only available to the
Blizzard UI"). So: Circle in chat empties the message and passes the press through so Blizzard
closes chat; outside chat, Send and Circle put the keyboard away and leave the field focused.
`/ebg show` reopens the keyboard on a field that is still focused.

The one exception is Send in chat, which sends, then closes chat and the keyboard. This was tested
on Forever (whispers and slash commands, then interacting with a guard, banker, auctioneer and
vendor) with no blocked action. Each close is noted in the blocked-action trail
("closeonsend DeactivateChat"), so if `/ebg blocked` ever shows a block after it,
`/ebg closeonsend off` returns to the old behaviour: Send leaves chat open and Circle closes it.

Enter and Escape on a physical keyboard are handled by Blizzard and close chat and the keyboard.
The keyboard stays open after losing focus only when the mouse was just pressed on it.

Bag and bank search are a second case: writing into that search box runs Blizzard's bag filter
as addon code and can cause the same block. EBG keeps the query in one shared buffer and calls
`C_Container.SetItemSearch`; it never writes to the real search box. A separate Item filter strip
shows the active query and a Clear button; Clear item filter is also reachable on the keyboard.
A post-hook observes native filter changes, including clearing, so cached text cannot overwrite
a newer native search. API failures retain the last successfully applied query and report an error.
`/ebg bagsearch` can no longer disable this protection, including through older saved settings.

Only named item-search fields and actual SearchBox/SearchBar children in bag/bank contexts use
the filter. Other native bank/guild-bank fields and native auction fields are excluded from EBG
typing until a dedicated adapter is validated; use their native controls. Auction search uses an
addon-owned buffer instead. There is no native Enter-handler escape hatch.

The established native arrow parking and legend fading are preserved. `/ebg pointer move|hide|off`
still controls the arrow. These visual behaviors are separate from the text-entry protections.

## Gamepad auction browser (0.23.1)

Visit an auctioneer with a gamepad, or run `/ebg ah`. `/ebg ah auto` toggles automatic opening.
The browser, its launcher button and `/ebg ah` are only available while the gamepad interface is
enabled; switching it off closes the browser. While the browser is open Blizzard's auction window
is faded to alpha 0 (it must stay open to keep the auction session) and restored on close;
`/ebg ah native` toggles that fade. While open, the browser keeps every pad button except the
system buttons (Menu, View, Social, System) so none can act on the faded window; Blizzard's
navigation pointer is faded with it. Entering combat closes the browser, because pad input cannot
be withheld from the game in combat.
The browser retains the metal frame and native glyphs, with auction-specific styling:
red native primary buttons, an inset search field, bottom view tabs, compact category rows,
and a striped results table. Categories, results, and item previews have separate backgrounds.
An amber marker identifies the applied category; a thin gold outline identifies controller
focus. These states remain independent when moving from the category tree into results.
Its Buy view keeps a category column on the left, search/filter controls at the top, and
Price / Name / Available result columns. Available is shown before selecting an item and comes
from the auction API's totalQuantity. Legacy listings use a clearly labeled Stack column instead
of claiming that a partial server page represents total market supply.

Categories are copied from Forever's native AuctionCategories data, preserving localized names,
order, subcategories, equipment slots, and their query filters. EBG stores expansion and selection
only in its own tables. A basic nine-category fallback is used if native data is unavailable.
Once a category is picked the list shows only its path and its subcategories; a Back button
under the list steps up one level. Selecting a category does not query the auction house: it clears the old results and waits for
Search, so several category steps cost one request instead of one each.
Sorting is done from the results' column headers, as in Blizzard's window: press Price, Name, or
(for gear) Req. Level to sort by it, and again to reverse; Price and Name re-run the current search
in the new order (Req. Level is sorted here; see below).
Filter opens a single page: the level range at the top, then checkboxes grouped as in Blizzard's
filter menu (general options; rarities in their quality colours). The Filter button shows how many
settings differ from the defaults. Apply and search submits these through the auction query API;
no native search handler or category mixin is called. Any (zero) means no level limit.

The level range is the level required to use the item ("Requires Level N"), not item level. The
modern browse query's own level fields are matched against item level on Forever, so they are
sent as "any" and `AuctionData` keeps only the browse results whose required level (from the
item's data) falls in the range. An item whose data has not loaded yet is held back, the load is
requested, and the results are read again as the data arrives (the status line says "checking
required levels" meanwhile). Items with no level requirement count as level 0, so any minimum
leaves them out. The legacy `QueryAuctionItems` takes the required level itself and still gets
the range directly.

The Level column ("Req. Level") is the required level too, and so is its sort. The server cannot
sort by required level (its own Level sort is item level, and on Forever it does not reorder the
results at all), so browse results are sorted by `AuctionFilters.SortByLevel` as they are read:
highest required level first on the first press, lowest first on the second, cheapest first among
equal levels, and items whose data has not loaded yet last (they move into place as it arrives).
With every result already loaded, pressing the header just re-sorts them with no new query.
Otherwise the search re-runs with the server's Level sort, so the first loads lean the right way,
and rows that Next loads are sorted in with the others.

Views: Buy (search, inspect, buy out or bid), Sell (auctionable bag items), Auctions (review and
cancel your listings; sold auctions stay listed greyed out, with the time until their gold reaches
the mailbox, and cannot be cancelled). Previous/Next are greyed out when there is no page in that
direction.

When the focused item is equipment, the item(s) you wear in that slot are shown under its tooltip
to compare, each headed "Equipped": both rings, both trinkets, both hands for a one-hand weapon,
main and off hand for a two-hander. Each ends with "If you replace this item:" and the stat changes
a swap would make, gains in green and losses in red (from `GetItemStats`; only stats with a display
name). The stack of tooltips is scaled down together to fit the preview pane. These are EBG's own
tooltips, filled with `SetInventoryItem`; Blizzard's shopping tooltips are not used.

The preview pane can show the focused item on your character instead of its tooltip: press R3
(right stick click) on any item that can be worn visibly, in Buy, Sell or Auctions. Your character
model appears dressed in your current gear with that item tried on; moving to another item tries
that one on instead, and R3 again returns to the tooltip (the middle mouse button on a row or on
the model does the same, for testing with a mouse; it is not shown anywhere). The choice stays while the browser is
open. Hold the right stick left or right to turn the model (or drag it with the mouse); the
further it is pushed, the faster the turn. While the right stick can turn the model, an indicator
sits at the bottom of the model: the right stick glyph between a left and a right arrow, the arrow
on the side being turned toward lit gold. Items that cannot be shown on a character (rings,
trinkets, potions...) keep their tooltip, and the legend offers R3 only when it applies. The model
is EBG's own `DressUpModel`, dressed with `SetUnit`, `Dress` and `TryOn`; Blizzard's dressing room
is never opened. The sticks are taken only while the model is on screen: the right stick (and the
camera stick the game derives from it) stays with the model, so the camera does not swing, and the
left stick is passed on, so it still moves you.

Modern item selection loads
individual auction/commodity rows. Native window closes the overlay without closing the auctioneer.
A launcher button and `/ebg ah` reopen it.

### Buying and selling (0.24)

The transaction panel follows Blizzard's Post Auctions layout: the form on the left, current
listings or details on the right. Every value is on screen and edited in place (one key each for
gold, silver, and copper; duration is three one-press choices). The main action starts focused
and Y performs it from anywhere; B goes back. Buttons are keyboard keys coloured by action:
green commits (Search, Create Auction, Buyout, Confirm), red gives something up (Cancel
Auction), gold enters money or bids, gray navigates.

Select a listing, then Buyout or Bid (the bid starts at the minimum). Commodities accept a quantity
(Max fills what is listed), request a live server quote, then show its actual total for confirmation.
Expired quotes cannot be accepted. Purchase confirmations start with Back selected, so a doubled A
press never buys; Y confirms. An updated quote resets selection and invalidates any held confirm
press. Item transactions recheck the auction ID, item, quantity, price, and funds.

Sell lists unlocked, auctionable items. Choosing one opens the form with the price already set to
the lowest current buyout, commodities at their full bag quantity, and the last duration used, so
posting at market price is: choose the item, press A on Create Auction. Picking a row in the
listings column copies its price. A price edited while the lookup is pending is preserved; if
nothing is listed, enter a price. Deposit and total update live. Create Auction validates and posts
in one press, as Blizzard's does. Item identity, quantity, deposit, and funds are checked on posting.
The posting API's additional confirmation requirement is honored with a second warning and
`ConfirmPostItem` / `ConfirmPostCommodity`; it is never automatically accepted. EBG dismisses
the stock posting notification for its own request because that popup accepts the stock sell
frame's pending post, not EBG's. Native popup definitions and scripts remain untouched.

Posting, buying, bidding and cancelling are only allowed inside a hardware input event, and a raw
gamepad button script is not one (calling `PostCommodity` from it is blocked as `UNKNOWN()`). While
the transaction panel is open, A, B and Y are therefore temporary override bindings that click
hidden EBG buttons; the browser lets those three presses through to them. The bindings are
removed when the panel closes, while the on-screen keyboard is open, and are never changed in combat.

Select an owned auction to see its cancellation fee; the form starts on Back, and Y (or A on Cancel Auction) cancels in one press. Confirmed operations wait for matching
server acknowledgements, handle errors and multisell progress, and never automatically retry.
An unknown outcome tells the player to check auctions, bags, and mail before trying again.
Another window's query or transaction invalidates a pending purchase instead of reusing stale
listing or quote state. Closing the auctioneer or entering combat dismisses the transaction UI.
Search/price keyboard dismissal synchronously restores browser input capture.

Transactions target Forever's modern `C_AuctionHouse` API. Legacy browsing remains available,
but legacy transactions still require the native window. No real purchases or sales are made by
the offline test suite; live secure-execution and visual checks remain required.

| Control | Action |
|---|---|
| D-pad up/down | Move selection |
| D-pad left/right | Move between categories and results, or adjacent controls |
| Cross / A | Activate selection (on release) |
| Circle / B | Back from filters/listings; otherwise close the auction house (the browser and Blizzard's window together; Blizzard's window is never left on screen in gamepad mode) |
| Square / X | Enter search using EBG's keyboard |
| Triangle / Y | Search again / refresh current view |
| L1 / R1 (LB / RB) | Change view |
| L2 / R2 (LT / RT) | Previous / next results page |
| R3 (right stick click) | Show the focused item on your character, or its tooltip again |
| Right stick left/right | Turn the character model (while it is shown) |

Requests respect server throttling and allow one pending query. Changing a query in another
window invalidates the displayed results. Timeouts and API errors produce visible recovery
messages. Closing the auctioneer also closes its composer and overlay. Combat disables actions;
capture is reconciled after combat even if the window closed during lockdown.

Implementation: AuctionFilters.lua owns category/filter snapshots, AuctionData.lua owns API
queries and result normalization, AuctionHouse.lua owns the controller frame. AuctionTransactions.lua
owns transaction validation and API state; AuctionTradeUI.lua owns the controller confirmation panel.
Modern and legacy APIs are detected independently.

The breadcrumb displays the full applied category path. Browse, listings, filters, selling,
and owned auctions each have a distinct heading and explanatory text. Listings
and filters expose an explicit Back control. Category controls appear only while browsing;
other views explain what their rows represent. Up from the first result returns to the search
toolbar, left/right moves between results and categories, and category navigation advances its
page when reaching the end. The item preview pane (Blizzard's tiled Necrolord background in a
bronze frame) shows only the focused item's own tooltip, scaled down when needed to fit, and its
quantity; with no item focused it fades to a faint outline. Prices use the gold, silver and copper
coin icons. AuctionStyle.lua owns this visual language independently
of the keyboard's key art.

## Item link picker

The chat keyboard's Items button (the bag icon, beside the quest icon) opens a read-only list of carried items with icons, rarity color,
combined counts for identical links, and an item tooltip. Cross/A inserts the exact link and
returns to typing. L1/R1 changes pages; Circle/B returns without clearing the message. Bag updates
refresh the picker. It never picks up, equips, moves, or sells an item.

The keyboard's bottom row also has a Reload key (the crossbar-edit icon). It closes the keyboard
and shows a confirmation pop-up (EBG's own, styled like Blizzard's, so Blizzard's shared pop-up
system is never tainted). A/Accept reloads the UI, the same as typing /reload; B, Cancel or Escape
dismisses it. ReloadUI is protected on this client, so Accept is a secure action button
running the macro `/reload`; while Accept is highlighted, A is an override binding to it (armed a
moment after the pop-up opens, so the press that opened it cannot accept it). It is not offered in
combat and closes when combat starts. It is
on every text field, not only chat. Opening the pop-up also closes chat (or releases the text
field), because key bindings do not fire while a field has focus and A would never reach Accept;
any unsent text is dropped, as the reload would drop it anyway.

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

The tabs update while the keyboard is open: joining or leaving a channel (including the zone
channels swapped on a zone change), group and guild changes, and chat colour changes redraw
them. Channel events come in bursts and the game's channel list can lag them, so the redraw
waits 0.2s and runs once per burst. If you leave the channel you are typing in, chat falls back
to Say instead of keeping a target that Send would fail on.

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

When no controller is identified in gamepad mode (no active device, or a "Generic" label style), a
PC defaults to PlayStation glyphs; a Mac keeps Xbox. Blizzard's legend is then not followed (it
draws Blizzard's own default), and a native prompt or icon that draws another family's art than
the expected atlas is refused, so EBG's PlayStation atlases are used throughout. `/ebg status`
says where the glyph style came from (settings, the controller, or the default).

Settings > Gamepad legend > Button glyphs (Automatic / PlayStation / Xbox) chooses the family
outright. A PlayStation pad used through Steam Input or DS4Windows is usually reported to the game
as an Xbox controller ("Letters"), so Automatic shows Xbox glyphs for it; choose PlayStation then.
A chosen family is never overridden by Blizzard's legend, and Blizzard's prompts and icons that
draw the other family's art (judged by the atlas name, e.g. `Gamepad-XB-...`, `gamepad-xb1-...`)
are refused in favour of EBG's own atlases. Changing it redraws the keyboard, the legends, the
auction browser's keys and this window at once.

## Skinning

`Skin.lua` builds the panel and preview box from Blizzard's own nine-slice layouts
(`NineSliceUtil.ApplyLayoutByName`) and the keys from `UIPanelButtonTemplate`, so the keyboard
inherits whatever art the Forever client ships and follows Blizzard's skin changes. Selection uses
the template's own locked highlight. Every path falls back to a flat backdrop if a template is missing.
Run `/ebg atlas ui`, copy the output, and the unit-frame atlases it lists can be dropped into the
presets in `Skin.lua` (or tried live with `/ebg glow <atlas>`).

## How it works

- `FocusTracker.lua` hooks OnEditFocusGained/Lost on every EditBox it can enumerate and polls
  `GetCurrentKeyBoardFocus()` every 0.1s as a catch-all. Forbidden frames are skipped. A focus
  gain on the field already tracked still offers the keyboard again, and its callbacks are
  wrapped so an error is reported once instead of breaking the poll.
- Loading: automatic opening is held off from load until 3s after entering the world or the end
  of each loading screen, with a 30s backstop so it can never stay held. While it is held, and
  whenever opening fails, the chat input is not faded, so chat is never left invisible with no
  keyboard. Each startup hook in `Core.lua` runs on its own and reports its own failure.
  `Bindings.xml` is loaded by the game itself and is not listed in the TOC.
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
3. Mail/profession/transmog text entry: header names the screen; Done keeps text and closes EBG. Submit using the native control.
4. Enter combat with the keyboard open: combat badge appears, mouse still works, pad resumes after combat.
5. If `GAME_PAD_ACTIVE_CHANGED` never fires on this build, `pad off` forces auto popup regardless.

### 0.23 live acceptance pass (not yet completed)

- The gamepad auction browser covers the native auction window, including its bottom tabs,
  and follows its position and scale. Its background intercepts mouse clicks. Verify the edges
  at your UI scale and after moving the native window; native window geometry is read only.
- From a clean `/reload`, search bags, clear, type with a physical keyboard in the native field,
  reopen EBG, switch to bank, and clear again. Verify the item filter strip and actual results agree.
- Exercise bag/bank item movement, splitting, deposits/withdrawals, sorting, closing/reopening,
  and subsequent gamepad navigation. Check `/ebg blocked`; collect the client's taint log if blocked.
- Search auctions by name and category; expand Weapons and Armor into nested categories/slots.
  Verify filters/levels/sort and Available counts against the native frame. Inspect commodity and
  equipment listings, page results, use Sell/Auctions (including a sold auction), and return to native controls.
- Buy one inexpensive item and a small commodity quantity, place a bid, post an item and a
  commodity, and cancel an owned auction. Check prices, deposits, confirmations, success/error
  messages, and mail. Exercise posting warnings, quote expiry, and inventory changes during review.
  Confirm no blocked actions or stale queries. Native queries should invalidate EBG's old results.
- Enter/leave combat and close either window during combat; test held-button release, keyboard
  submit/cancel, and mouse/controller switching. Verify the arrow restores its original anchor.
- Repeat with EBG alone, then the normal addon set. A clean blocked-action list alone does not
  establish absence of taint; live secure-execution behavior cannot be modeled by unit tests.

### Offline regression checks

`python tests/run.py [directory containing lupa]` uses lupa's Lua 5.1 runtime. It parses every
addon Lua file and exercises search isolation/synchronization, API failure, combat guards, item
links, owned composers, auction throttling/timeouts/paging, availability labels, category copying,
query filters, external-query invalidation, and arrow restoration using a small mock host.
Transaction checks cover explicit confirmation, live quotes, price changes, expired quotes,
funds, inventory identity, deposits, posting warnings, multisell, cancellation, server errors,
duplicate submission, external transaction interference, and synchronous input handoff.
These checks do not render WoW or certify taint-free operation.

API reference: [Forever auction category data](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Camelot/Blizzard_AuctionData.lua),
[Forever search bar](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseSearchBar.lua).
Transaction references: [Forever auction API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua),
[commodity confirmation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseBuyDialog.lua),
[item posting confirmation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseItemSellFrame.lua).
