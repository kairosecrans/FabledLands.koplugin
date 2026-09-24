local _ = require("gettext")
return {
    fullname = _("Fabled Lands"),
    -- KOReader does not read this; it is here so a shipped copy can be
    -- identified from a bug report.
    version = "0.5.0-alpha",
    description = _([[Keeps the Adventure Sheet for the Fabled Lands gamebooks: abilities, Stamina, Defence, possessions and codewords. Rolls ability checks and runs fights round by round so you never have to reach for dice.]]),
}
