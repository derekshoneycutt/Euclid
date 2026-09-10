# Euclid terminfo

`euclid.terminfo` contains only capabilities backed by tests and the capability
matrix at the repository root. Rebuild the packaged ncurses entry from the repository
root after changing the source:

```sh
tic -x -o assets/terminfo assets/terminfo/euclid.terminfo
```

The repository retains entries compiled by both current Linux ncurses under
`t/euclid` and Apple ncurses under `74/euclid`. Development changes to the
source must regenerate and commit both entries on their respective hosts. Apple ncurses
6.0 stores the `colors` numeric capability as `32767`, but retains `RGB` and expands the
profile's indexed and direct-color controls correctly.

Terminal-attached child processes receive `TERM=euclid`, `COLORTERM=truecolor`,
and an absolute `TERMINFO` path. The profile publishes ANSI, indexed, and direct RGB
colors. It intentionally omits static dimensions, device reports, hyperlinks, clipboard
access, and window operations. It publishes three-button SGR mouse input with button and
button-motion tracking; Shift retains local selection and scrolling. DEC 1003 any-event
tracking is implemented through explicit child negotiation but remains absent from the
profile's `XM` capability.
Xterm `modifyOtherKeys` levels 1 and 2 are likewise available
only through explicit child negotiation and query. They do not add a terminfo capability
or change the packaged profile, so applications that need modified ordinary-key reports
must emit the xterm control sequences directly.
Kitty keyboard replace, set, clear, query, push, and pop negotiation accepts
disambiguation flag 1 and event-type flag 2. Its state and bounded stack are
screen-local. DA1 reports `CSI ? 62 ; 4 c`, identifying VT340-class behavior and Sixel
support, and the extended terminfo profile publishes the standard `sixel` boolean.
Repeat and release types are emitted only for keys already represented by escape
sequences; ordinary text and the Enter, Tab, and Backspace recovery path stay legacy.
Kitty graphics queries receive bounded producer-correlated replies, while Kitty graphics
and iTerm2 inline images remain absent from terminfo and the child environment. Programs
using those protocols must probe them directly.
