# KOReader Instant Dictionary

When this plugin is enabled, a single press on a word will open the dictionary instead of a long press.

The dictionary is opened by calling onHold and onHoldRelease, so the short press on a word is interpreted as if it were a long press, and then the dictionary is forced as default handling for a long press.

The plugin makes the following adjustmens to the default lookup behaviour:
1. Highlight will be ignored if the touch position is too far away from a word
2. Highlight will be ignored if it consists of ignored characters (mainly punctuation, quotation makrs)

Futher, touches within the statusbar will be ignored.

## Install

Download this repository, extract the zip file and move _instantdictionary.koplugin_ inside your KOReader _plugins_ folder and copy all the files from this repository into it.
Make sure the plugin is enabled under _Main Menu_ > _Options_ > _More Tools_ > _Plugin Management_.

The plugin offers no configuration methods in KOReader.
