//
//Simple DirectMedia Layer
//Copyright (C) 1997-2023 Sam Lantinga <slouken@libsdl.org>

//This software is provided 'as-is', without any express or implied
//warranty.  In no event will the authors be held liable for any damages
//arising from the use of this software.

//Permission is granted to anyone to use this software for any purpose,
//including commercial applications, and to alter it and redistribute it
//freely, subject to the following restrictions:

//1. The origin of this software must not be misrepresented; you must not
//   claim that you wrote the original software. If you use this software
//   in a product, an acknowledgment in the product documentation would be
//   appreciated but is not required.
//2. Altered source versions must be plainly marked as such, and must not be
//   misrepresented as being the original software.
//3. This notice may not be removed or altered from any source distribution.
//

//
// modified from SDL_scancode.h and SDL_keycode.h
// Defines keyboard scancodes.
//

//
// \brief The SDL keyboard scancode representation.
//
// Values of this type are used to represent keyboard keys, among other places
// in the \link SDL_Keysym::scancode key.keysym.scancode \endlink field of the
// SDL_Event structure.
//
// The values in this enumeration are based on the USB usage page standard:
// https://www.usb.org/sites/default/files/documents/hut1_12v2.pdf
//
const std = @import("std");
pub const Scancode = enum(u32) {
    UNKNOWN = 0,

    //
    // Usage page 0x07
    //
    // These values are from usage page 0x07 (USB keyboard page).
    //
    //

    A = 4,
    B = 5,
    C = 6,
    D = 7,
    E = 8,
    F = 9,
    G = 10,
    H = 11,
    I = 12,
    J = 13,
    K = 14,
    L = 15,
    M = 16,
    N = 17,
    O = 18,
    P = 19,
    Q = 20,
    R = 21,
    S = 22,
    T = 23,
    U = 24,
    V = 25,
    W = 26,
    X = 27,
    Y = 28,
    Z = 29,

    _1 = 30,
    _2 = 31,
    _3 = 32,
    _4 = 33,
    _5 = 34,
    _6 = 35,
    _7 = 36,
    _8 = 37,
    _9 = 38,
    _0 = 39,

    RETURN = 40,
    ESCAPE = 41,
    BACKSPACE = 42,
    TAB = 43,
    SPACE = 44,

    MINUS = 45,
    EQUALS = 46,
    LEFTBRACKET = 47,
    RIGHTBRACKET = 48,
    BACKSLASH = 49, // Located at the lower left of the return
    //  key on ISO keyboards and at the right end
    //  of the QWERTY row on ANSI keyboards.
    //  Produces REVERSE SOLIDUS (backslash) and
    //  VERTICAL LINE in a US layout, REVERSE
    //  SOLIDUS and VERTICAL LINE in a UK Mac
    //  layout, NUMBER SIGN and TILDE in a UK
    //  Windows layout, DOLLAR SIGN and POUND SIGN
    //  in a Swiss German layout, NUMBER SIGN and
    //  APOSTROPHE in a German layout, GRAVE
    //  ACCENT and POUND SIGN in a French Mac
    //  layout, and ASTERISK and MICRO SIGN in a
    //  French Windows layout.
    //
    NONUSHASH = 50, //< ISO USB keyboards actually use this code
    //  instead of 49 for the same key, but all
    //  OSes I've seen treat the two codes
    //  identically. So, as an implementor, unless
    //  your keyboard generates both of those
    //  codes and your OS treats them differently,
    //  you should generate SDL_SCANCODE_BACKSLASH
    //  instead of this code. As a user, you
    //  should not rely on this code because SDL
    //  will never generate it with most (all?)
    //  keyboards.
    //
    SEMICOLON = 51,
    APOSTROPHE = 52,
    GRAVE = 53, //< Located in the top left corner (on both ANSI
    //  and ISO keyboards). Produces GRAVE ACCENT and
    //  TILDE in a US Windows layout and in US and UK
    //  Mac layouts on ANSI keyboards, GRAVE ACCENT
    //  and NOT SIGN in a UK Windows layout, SECTION
    //  SIGN and PLUS-MINUS SIGN in US and UK Mac
    //  layouts on ISO keyboards, SECTION SIGN and
    //  DEGREE SIGN in a Swiss German layout (Mac:
    //  only on ISO keyboards), CIRCUMFLEX ACCENT and
    //  DEGREE SIGN in a German layout (Mac: only on
    //  ISO keyboards), SUPERSCRIPT TWO and TILDE in a
    //  French Windows layout, COMMERCIAL AT and
    //  NUMBER SIGN in a French Mac layout on ISO
    //  keyboards, and LESS-THAN SIGN and GREATER-THAN
    //  SIGN in a Swiss German, German, or French Mac
    //  layout on ANSI keyboards.
    //
    COMMA = 54,
    PERIOD = 55,
    SLASH = 56,

    CAPSLOCK = 57,

    F1 = 58,
    F2 = 59,
    F3 = 60,
    F4 = 61,
    F5 = 62,
    F6 = 63,
    F7 = 64,
    F8 = 65,
    F9 = 66,
    F10 = 67,
    F11 = 68,
    F12 = 69,

    PRINTSCREEN = 70,
    SCROLLLOCK = 71,
    PAUSE = 72,
    INSERT = 73, //*< insert on PC, help on some Mac keyboards (but
    //  does send code 73, not 117) */
    HOME = 74,
    PAGEUP = 75,
    DELETE = 76,
    END = 77,
    PAGEDOWN = 78,
    RIGHT = 79,
    LEFT = 80,
    DOWN = 81,
    UP = 82,

    NUMLOCKCLEAR = 83, //< num lock on PC, clear on Mac keyboards

    KP_DIVIDE = 84,
    KP_MULTIPLY = 85,
    KP_MINUS = 86,
    KP_PLUS = 87,
    KP_ENTER = 88,
    KP_1 = 89,
    KP_2 = 90,
    KP_3 = 91,
    KP_4 = 92,
    KP_5 = 93,
    KP_6 = 94,
    KP_7 = 95,
    KP_8 = 96,
    KP_9 = 97,
    KP_0 = 98,
    KP_PERIOD = 99,

    NONUSBACKSLASH = 100, //*< This is the additional key that ISO
    //   keyboards have over ANSI ones,
    //   located between left shift and Y.
    //   Produces GRAVE ACCENT and TILDE in a
    //   US or UK Mac layout, REVERSE SOLIDUS
    //   (backslash) and VERTICAL LINE in a
    //   US or UK Windows layout, and
    //   LESS-THAN SIGN and GREATER-THAN SIGN
    //   in a Swiss German, German, or French
    //   layout. */
    APPLICATION = 101, //< windows contextual menu, compose */
    POWER = 102, //< The USB document says this is a status flag,
    //   not a physical key - but some Mac keyboards
    //   do have a power key. */
    KP_EQUALS = 103,
    F13 = 104,
    F14 = 105,
    F15 = 106,
    F16 = 107,
    F17 = 108,
    F18 = 109,
    F19 = 110,
    F20 = 111,
    F21 = 112,
    F22 = 113,
    F23 = 114,
    F24 = 115,
    EXECUTE = 116,
    HELP = 117, //*< AL Integrated Help Center */
    MENU = 118, //*< Menu (show menu) */
    SELECT = 119,
    STOP = 120, //*< AC Stop */
    AGAIN = 121, //*< AC Redo/Repeat */
    UNDO = 122, //*< AC Undo */
    CUT = 123, //*< AC Cut */
    COPY = 124, //*< AC Copy */
    PASTE = 125, //*< AC Paste */
    FIND = 126, //*< AC Find */
    MUTE = 127,
    VOLUMEUP = 128,
    VOLUMEDOWN = 129,
    KP_COMMA = 133,
    KP_EQUALSAS400 = 134,

    INTERNATIONAL1 = 135, //*< used on Asian keyboards, see
    //    footnotes in USB doc */
    INTERNATIONAL2 = 136,
    INTERNATIONAL3 = 137, //*< Yen */
    INTERNATIONAL4 = 138,
    INTERNATIONAL5 = 139,
    INTERNATIONAL6 = 140,
    INTERNATIONAL7 = 141,
    INTERNATIONAL8 = 142,
    INTERNATIONAL9 = 143,
    LANG1 = 144, //*< Hangul/English toggle */
    LANG2 = 145, //*< Hanja conversion */
    LANG3 = 146, //*< Katakana */
    LANG4 = 147, //*< Hiragana */
    LANG5 = 148, //*< Zenkaku/Hankaku */
    LANG6 = 149, //*< reserved */
    LANG7 = 150, //*< reserved */
    LANG8 = 151, //*< reserved */
    LANG9 = 152, //*< reserved */

    ALTERASE = 153, //*< Erase-Eaze */
    SYSREQ = 154,
    CANCEL = 155, //*< AC Cancel */
    CLEAR = 156,
    PRIOR = 157,
    RETURN2 = 158,
    SEPARATOR = 159,
    OUT = 160,
    OPER = 161,
    CLEARAGAIN = 162,
    CRSEL = 163,
    EXSEL = 164,

    KP_00 = 176,
    KP_000 = 177,
    THOUSANDSSEPARATOR = 178,
    DECIMALSEPARATOR = 179,
    CURRENCYUNIT = 180,
    CURRENCYSUBUNIT = 181,
    KP_LEFTPAREN = 182,
    KP_RIGHTPAREN = 183,
    KP_LEFTBRACE = 184,
    KP_RIGHTBRACE = 185,
    KP_TAB = 186,
    KP_BACKSPACE = 187,
    KP_A = 188,
    KP_B = 189,
    KP_C = 190,
    KP_D = 191,
    KP_E = 192,
    KP_F = 193,
    KP_XOR = 194,
    KP_POWER = 195,
    KP_PERCENT = 196,
    KP_LESS = 197,
    KP_GREATER = 198,
    KP_AMPERSAND = 199,
    KP_DBLAMPERSAND = 200,
    KP_VERTICALBAR = 201,
    KP_DBLVERTICALBAR = 202,
    KP_COLON = 203,
    KP_HASH = 204,
    KP_SPACE = 205,
    KP_AT = 206,
    KP_EXCLAM = 207,
    KP_MEMSTORE = 208,
    KP_MEMRECALL = 209,
    KP_MEMCLEAR = 210,
    KP_MEMADD = 211,
    KP_MEMSUBTRACT = 212,
    KP_MEMMULTIPLY = 213,
    KP_MEMDIVIDE = 214,
    KP_PLUSMINUS = 215,
    KP_CLEAR = 216,
    KP_CLEARENTRY = 217,
    KP_BINARY = 218,
    KP_OCTAL = 219,
    KP_DECIMAL = 220,
    KP_HEXADECIMAL = 221,

    LCTRL = 224,
    LSHIFT = 225,
    LALT = 226, //*< alt, option */
    LGUI = 227, //*< windows, command (apple), meta */
    RCTRL = 228,
    RSHIFT = 229,
    RALT = 230, //*< alt gr, option */
    RGUI = 231, //*< windows, command (apple), meta */

    MODE = 257, //*< I'm not sure if this is really not covered
    //  by any of the above, but since there's a
    //  special KMOD_MODE for it I'm adding it here
    //

    //*
    //  \name Usage page 0x0C
    //
    //  These values are mapped from usage page 0x0C (USB consumer page).
    //  See https://usb.org/sites/default/files/hut1_2.pdf
    //
    //  There are way more keys in the spec than we can represent in the
    //  current scancode range, so pick the ones that commonly come up in
    //  real world usage.
    //
    // @{ */

    AUDIONEXT = 258,
    AUDIOPREV = 259,
    AUDIOSTOP = 260,
    AUDIOPLAY = 261,
    AUDIOMUTE = 262,
    MEDIASELECT = 263,
    WWW = 264, //< AL Internet Browser */
    MAIL = 265,
    CALCULATOR = 266, //< AL Calculator */
    COMPUTER = 267,
    AC_SEARCH = 268, //< AC Search */
    AC_HOME = 269, //< AC Home */
    AC_BACK = 270, //< AC Back */
    AC_FORWARD = 271, //< AC Forward */
    AC_STOP = 272, //< AC Stop */
    AC_REFRESH = 273, //< AC Refresh */
    AC_BOOKMARKS = 274, //< AC Bookmarks */

    //*
    //  \name Walther keys
    //
    //  These are values that Christian Walther added (for mac keyboard?).
    //

    BRIGHTNESSDOWN = 275,
    BRIGHTNESSUP = 276,
    DISPLAYSWITCH = 277, //< display mirroring/dual display
    //switch, video mode switch */
    KBDILLUMTOGGLE = 278,
    KBDILLUMDOWN = 279,
    KBDILLUMUP = 280,
    EJECT = 281,
    SLEEP = 282, //< SC System Sleep */

    APP1 = 283,
    APP2 = 284,

    // @} *//* Walther keys */

    //*
    //  \name Usage page 0x0C (additional media keys)
    //
    //  These values are mapped from usage page 0x0C (USB consumer page).
    //
    // @{ */

    AUDIOREWIND = 285,
    AUDIOFASTFORWARD = 286,

    // @} *//* Usage page 0x0C (additional media keys) */

    //
    // \name Mobile keys
    //
    // These are values that are often used on mobile phones.
    //
    //@{ */

    SOFTLEFT = 287, //< Usually situated below the display on phones and
    //              used as a multi-function feature key for selecting
    //              a software defined function shown on the bottom left
    //              of the display. */
    SOFTRIGHT = 288, //*< Usually situated below the display on phones and
    //              used as a multi-function feature key for selecting
    //              a software defined function shown on the bottom right
    //              of the display. */
    CALL = 289, //*< Used for accepting phone calls. */
    ENDCALL = 290, //*< Used for rejecting phone calls. */

    //* @} *//* Mobile keys */

    //* Add any other keys here. */

    ODES = 512, //< not a key, just marks the number of scancodes for array bounds */
};

//
//  \brief The SDL virtual key representation.
//
//  Values of this type are used to represent keyboard keys using the current
//  layout of the keyboard.  These values include Unicode values representing
//  the unmodified character that would be generated by pressing the key, or
//  an SDLK_* constant for those keys that do not generate characters.
//
//  A special exception is the number keys at the top of the keyboard which
//  always map to SDLK_0...SDLK_9, regardless of layout.
//

const SDLK_SCANCODE_MASK = (1 << 30);
fn scanToKey(comptime x: Scancode) u32 {
    return @intFromEnum(x) | SDLK_SCANCODE_MASK;
}

pub const Keycode = enum(u32) {
    UNKNOWN = 0,

    RETURN = '\r',
    ESCAPE = '\x1B',
    BACKSPACE = '\x08',
    TAB = '\t',
    SPACE = ' ',
    EXCLAIM = '!',
    QUOTEDBL = '"',
    HASH = '#',
    PERCENT = '%',
    DOLLAR = '$',
    AMPERSAND = '&',
    QUOTE = '\'',
    LEFTPAREN = '(',
    RIGHTPAREN = ')',
    ASTERISK = '*',
    PLUS = '+',
    COMMA = ',',
    MINUS = '-',
    PERIOD = '.',
    SLASH = '/',
    _0 = '0',
    _1 = '1',
    _2 = '2',
    _3 = '3',
    _4 = '4',
    _5 = '5',
    _6 = '6',
    _7 = '7',
    _8 = '8',
    _9 = '9',
    COLON = ':',
    SEMICOLON = ';',
    LESS = '<',
    EQUALS = '=',
    GREATER = '>',
    QUESTION = '?',
    AT = '@',

    LEFTBRACKET = '[',
    BACKSLASH = '\\',
    RIGHTBRACKET = ']',
    CARET = '^',
    UNDERSCORE = '_',
    BACKQUOTE = '`',
    a = 'a',
    b = 'b',
    c = 'c',
    d = 'd',
    e = 'e',
    f = 'f',
    g = 'g',
    h = 'h',
    i = 'i',
    j = 'j',
    k = 'k',
    l = 'l',
    m = 'm',
    n = 'n',
    o = 'o',
    p = 'p',
    q = 'q',
    r = 'r',
    s = 's',
    t = 't',
    u = 'u',
    v = 'v',
    w = 'w',
    x = 'x',
    y = 'y',
    z = 'z',

    CAPSLOCK = scanToKey(Scancode.CAPSLOCK),

    F1 = scanToKey(Scancode.F1),
    F2 = scanToKey(Scancode.F2),
    F3 = scanToKey(Scancode.F3),
    F4 = scanToKey(Scancode.F4),
    F5 = scanToKey(Scancode.F5),
    F6 = scanToKey(Scancode.F6),
    F7 = scanToKey(Scancode.F7),
    F8 = scanToKey(Scancode.F8),
    F9 = scanToKey(Scancode.F9),
    F10 = scanToKey(Scancode.F10),
    F11 = scanToKey(Scancode.F11),
    F12 = scanToKey(Scancode.F12),

    PRINTSCREEN = scanToKey(Scancode.PRINTSCREEN),
    SCROLLLOCK = scanToKey(Scancode.SCROLLLOCK),
    PAUSE = scanToKey(Scancode.PAUSE),
    INSERT = scanToKey(Scancode.INSERT),
    HOME = scanToKey(Scancode.HOME),
    PAGEUP = scanToKey(Scancode.PAGEUP),
    DELETE = '\x7F',
    END = scanToKey(Scancode.END),
    PAGEDOWN = scanToKey(Scancode.PAGEDOWN),
    RIGHT = scanToKey(Scancode.RIGHT),
    LEFT = scanToKey(Scancode.LEFT),
    DOWN = scanToKey(Scancode.DOWN),
    UP = scanToKey(Scancode.UP),

    NUMLOCKCLEAR = scanToKey(Scancode.NUMLOCKCLEAR),
    KP_DIVIDE = scanToKey(Scancode.KP_DIVIDE),
    KP_MULTIPLY = scanToKey(Scancode.KP_MULTIPLY),
    KP_MINUS = scanToKey(Scancode.KP_MINUS),
    KP_PLUS = scanToKey(Scancode.KP_PLUS),
    KP_ENTER = scanToKey(Scancode.KP_ENTER),
    KP_1 = scanToKey(Scancode.KP_1),
    KP_2 = scanToKey(Scancode.KP_2),
    KP_3 = scanToKey(Scancode.KP_3),
    KP_4 = scanToKey(Scancode.KP_4),
    KP_5 = scanToKey(Scancode.KP_5),
    KP_6 = scanToKey(Scancode.KP_6),
    KP_7 = scanToKey(Scancode.KP_7),
    KP_8 = scanToKey(Scancode.KP_8),
    KP_9 = scanToKey(Scancode.KP_9),
    KP_0 = scanToKey(Scancode.KP_0),
    KP_PERIOD = scanToKey(Scancode.KP_PERIOD),

    APPLICATION = scanToKey(Scancode.APPLICATION),
    POWER = scanToKey(Scancode.POWER),
    KP_EQUALS = scanToKey(Scancode.KP_EQUALS),
    F13 = scanToKey(Scancode.F13),
    F14 = scanToKey(Scancode.F14),
    F15 = scanToKey(Scancode.F15),
    F16 = scanToKey(Scancode.F16),
    F17 = scanToKey(Scancode.F17),
    F18 = scanToKey(Scancode.F18),
    F19 = scanToKey(Scancode.F19),
    F20 = scanToKey(Scancode.F20),
    F21 = scanToKey(Scancode.F21),
    F22 = scanToKey(Scancode.F22),
    F23 = scanToKey(Scancode.F23),
    F24 = scanToKey(Scancode.F24),
    EXECUTE = scanToKey(Scancode.EXECUTE),
    HELP = scanToKey(Scancode.HELP),
    MENU = scanToKey(Scancode.MENU),
    SELECT = scanToKey(Scancode.SELECT),
    STOP = scanToKey(Scancode.STOP),
    AGAIN = scanToKey(Scancode.AGAIN),
    UNDO = scanToKey(Scancode.UNDO),
    CUT = scanToKey(Scancode.CUT),
    COPY = scanToKey(Scancode.COPY),
    PASTE = scanToKey(Scancode.PASTE),
    FIND = scanToKey(Scancode.FIND),
    MUTE = scanToKey(Scancode.MUTE),
    VOLUMEUP = scanToKey(Scancode.VOLUMEUP),
    VOLUMEDOWN = scanToKey(Scancode.VOLUMEDOWN),
    KP_COMMA = scanToKey(Scancode.KP_COMMA),
    KP_EQUALSAS400 = scanToKey(Scancode.KP_EQUALSAS400),

    ALTERASE = scanToKey(Scancode.ALTERASE),
    SYSREQ = scanToKey(Scancode.SYSREQ),
    CANCEL = scanToKey(Scancode.CANCEL),
    CLEAR = scanToKey(Scancode.CLEAR),
    PRIOR = scanToKey(Scancode.PRIOR),
    RETURN2 = scanToKey(Scancode.RETURN2),
    SEPARATOR = scanToKey(Scancode.SEPARATOR),
    OUT = scanToKey(Scancode.OUT),
    OPER = scanToKey(Scancode.OPER),
    CLEARAGAIN = scanToKey(Scancode.CLEARAGAIN),
    CRSEL = scanToKey(Scancode.CRSEL),
    EXSEL = scanToKey(Scancode.EXSEL),

    KP_00 = scanToKey(Scancode.KP_00),
    KP_000 = scanToKey(Scancode.KP_000),
    THOUSANDSSEPARATOR = scanToKey(Scancode.THOUSANDSSEPARATOR),
    DECIMALSEPARATOR = scanToKey(Scancode.DECIMALSEPARATOR),
    CURRENCYUNIT = scanToKey(Scancode.CURRENCYUNIT),
    CURRENCYSUBUNIT = scanToKey(Scancode.CURRENCYSUBUNIT),
    KP_LEFTPAREN = scanToKey(Scancode.KP_LEFTPAREN),
    KP_RIGHTPAREN = scanToKey(Scancode.KP_RIGHTPAREN),
    KP_LEFTBRACE = scanToKey(Scancode.KP_LEFTBRACE),
    KP_RIGHTBRACE = scanToKey(Scancode.KP_RIGHTBRACE),
    KP_TAB = scanToKey(Scancode.KP_TAB),
    KP_BACKSPACE = scanToKey(Scancode.KP_BACKSPACE),
    KP_A = scanToKey(Scancode.KP_A),
    KP_B = scanToKey(Scancode.KP_B),
    KP_C = scanToKey(Scancode.KP_C),
    KP_D = scanToKey(Scancode.KP_D),
    KP_E = scanToKey(Scancode.KP_E),
    KP_F = scanToKey(Scancode.KP_F),
    KP_XOR = scanToKey(Scancode.KP_XOR),
    KP_POWER = scanToKey(Scancode.KP_POWER),
    KP_PERCENT = scanToKey(Scancode.KP_PERCENT),
    KP_LESS = scanToKey(Scancode.KP_LESS),
    KP_GREATER = scanToKey(Scancode.KP_GREATER),
    KP_AMPERSAND = scanToKey(Scancode.KP_AMPERSAND),
    KP_DBLAMPERSAND = scanToKey(Scancode.KP_DBLAMPERSAND),
    KP_VERTICALBAR = scanToKey(Scancode.KP_VERTICALBAR),
    KP_DBLVERTICALBAR = scanToKey(Scancode.KP_DBLVERTICALBAR),
    KP_COLON = scanToKey(Scancode.KP_COLON),
    KP_HASH = scanToKey(Scancode.KP_HASH),
    KP_SPACE = scanToKey(Scancode.KP_SPACE),
    KP_AT = scanToKey(Scancode.KP_AT),
    KP_EXCLAM = scanToKey(Scancode.KP_EXCLAM),
    KP_MEMSTORE = scanToKey(Scancode.KP_MEMSTORE),
    KP_MEMRECALL = scanToKey(Scancode.KP_MEMRECALL),
    KP_MEMCLEAR = scanToKey(Scancode.KP_MEMCLEAR),
    KP_MEMADD = scanToKey(Scancode.KP_MEMADD),
    KP_MEMSUBTRACT = scanToKey(Scancode.KP_MEMSUBTRACT),
    KP_MEMMULTIPLY = scanToKey(Scancode.KP_MEMMULTIPLY),
    KP_MEMDIVIDE = scanToKey(Scancode.KP_MEMDIVIDE),
    KP_PLUSMINUS = scanToKey(Scancode.KP_PLUSMINUS),
    KP_CLEAR = scanToKey(Scancode.KP_CLEAR),
    KP_CLEARENTRY = scanToKey(Scancode.KP_CLEARENTRY),
    KP_BINARY = scanToKey(Scancode.KP_BINARY),
    KP_OCTAL = scanToKey(Scancode.KP_OCTAL),
    KP_DECIMAL = scanToKey(Scancode.KP_DECIMAL),
    KP_HEXADECIMAL = scanToKey(Scancode.KP_HEXADECIMAL),

    LCTRL = scanToKey(Scancode.LCTRL),
    LSHIFT = scanToKey(Scancode.LSHIFT),
    LALT = scanToKey(Scancode.LALT),
    LGUI = scanToKey(Scancode.LGUI),
    RCTRL = scanToKey(Scancode.RCTRL),
    RSHIFT = scanToKey(Scancode.RSHIFT),
    RALT = scanToKey(Scancode.RALT),
    RGUI = scanToKey(Scancode.RGUI),

    MODE = scanToKey(Scancode.MODE),

    AUDIONEXT = scanToKey(Scancode.AUDIONEXT),
    AUDIOPREV = scanToKey(Scancode.AUDIOPREV),
    AUDIOSTOP = scanToKey(Scancode.AUDIOSTOP),
    AUDIOPLAY = scanToKey(Scancode.AUDIOPLAY),
    AUDIOMUTE = scanToKey(Scancode.AUDIOMUTE),
    MEDIASELECT = scanToKey(Scancode.MEDIASELECT),
    WWW = scanToKey(Scancode.WWW),
    MAIL = scanToKey(Scancode.MAIL),
    CALCULATOR = scanToKey(Scancode.CALCULATOR),
    COMPUTER = scanToKey(Scancode.COMPUTER),
    AC_SEARCH = scanToKey(Scancode.AC_SEARCH),
    AC_HOME = scanToKey(Scancode.AC_HOME),
    AC_BACK = scanToKey(Scancode.AC_BACK),
    AC_FORWARD = scanToKey(Scancode.AC_FORWARD),
    AC_STOP = scanToKey(Scancode.AC_STOP),
    AC_REFRESH = scanToKey(Scancode.AC_REFRESH),
    AC_BOOKMARKS = scanToKey(Scancode.AC_BOOKMARKS),

    BRIGHTNESSDOWN = scanToKey(Scancode.BRIGHTNESSDOWN),
    BRIGHTNESSUP = scanToKey(Scancode.BRIGHTNESSUP),
    DISPLAYSWITCH = scanToKey(Scancode.DISPLAYSWITCH),
    KBDILLUMTOGGLE = scanToKey(Scancode.KBDILLUMTOGGLE),
    KBDILLUMDOWN = scanToKey(Scancode.KBDILLUMDOWN),
    KBDILLUMUP = scanToKey(Scancode.KBDILLUMUP),
    EJECT = scanToKey(Scancode.EJECT),
    SLEEP = scanToKey(Scancode.SLEEP),
    APP1 = scanToKey(Scancode.APP1),
    APP2 = scanToKey(Scancode.APP2),

    AUDIOREWIND = scanToKey(Scancode.AUDIOREWIND),
    AUDIOFASTFORWARD = scanToKey(Scancode.AUDIOFASTFORWARD),

    SOFTLEFT = scanToKey(Scancode.SOFTLEFT),
    SOFTRIGHT = scanToKey(Scancode.SOFTRIGHT),
    CALL = scanToKey(Scancode.CALL),
    ENDCALL = scanToKey(Scancode.ENDCALL),
};

//
// \brief Enumeration of valid key mods (possibly OR'd together).
pub const KM_LCTRL = 0x0040;
pub const KM_RCTRL = 0x0080;
pub const KM_LSHIFT = 0x0001;
pub const KM_RSHIFT = 0x0002;
pub const KM_LALT = 0x0100;
pub const KM_RALT = 0x0200;
pub const KM_LGUI = 0x0400;
pub const KM_RGUI = 0x0800;
pub const KM_SCROLL = 0x8000;
pub const KeymodMask = u32;
pub const Keymod = enum(KeymodMask) {
    NONE = 0x0000,
    LSHIFT = KM_LSHIFT,
    RSHIFT = KM_RSHIFT,
    LCTRL = KM_LCTRL,
    RCTRL = KM_RCTRL,
    LALT = KM_LALT,
    RALT = KM_RALT,
    LGUI = KM_LGUI,
    RGUI = KM_RGUI,
    NUM = 0x1000,
    CAPS = 0x2000,
    MODE = 0x4000,
    SCROLL = KM_SCROLL,

    CTRL = KM_LCTRL | KM_RCTRL,
    SHIFT = KM_LSHIFT | KM_RSHIFT,
    ALT = KM_LALT | KM_RALT,
    GUI = KM_LGUI | KM_RGUI,

    pub fn mask(to_mask: []const Keymod) KeymodMask {
        var ret: KeymodMask = 0;
        for (to_mask) |t|
            ret |= @intFromEnum(t);
        return ret;
    }

    pub fn name(mask_: KeymodMask, buf: []u8) []const u8 {
        var fbs = std.io.FixedBufferStream([]u8){ .buffer = buf, .pos = 0 };
        const info = @typeInfo(Keymod);
        const fi = info.@"enum".fields[12..];
        inline for (fi) |f| {
            if (f.value & mask_ > 0) {
                fbs.writer().print("{s} ", .{@tagName(@as(Keymod, @enumFromInt(f.value)))}) catch {};
            }
        }
        return fbs.getWritten();
    }

    pub fn fromScancode(scancode: Scancode) KeymodMask {
        return @intFromEnum(switch (scancode) {
            else => Keymod.NONE,
            .LSHIFT => Keymod.LSHIFT,
            .RSHIFT => Keymod.RSHIFT,
            .LCTRL => Keymod.LCTRL,
            .RCTRL => Keymod.RCTRL,
            .LALT => Keymod.LALT,
            .RALT => Keymod.RALT,
            .LGUI => Keymod.LGUI,
            .RGUI => Keymod.RGUI,
            .NUMLOCKCLEAR => Keymod.NUM,
            .CAPSLOCK => Keymod.CAPS,
            .SCROLLLOCK => Keymod.SCROLL,
        });
    }
};

pub const MouseButton = enum(u8) {
    left = 1,
    middle = 2,
    right = 3,
    x1 = 4,
    x2 = 5,
    max_mouse_btn = std.math.maxInt(u8),
    _, //SDL seems to support 1-255 mouse buttons
};
