# KOReader Instant Dictionary

When this plugin is enabled, a single press on a word will open the dictionary instead of a long press.

The dictionary is opened by calling onHold and onHoldRelease, so the short press on a word is interpreted as if it were a long press, and then the dictionary is forced as default handling for a long press.

The plugin makes the following adjustmens to the default lookup behaviour:
1. Highlight will be ignored if the touch position is too far away from a word
2. Highlight will be ignored if it consists of ignored characters (mainly punctuation, quotation makrs)

Futher, touches within the statusbar will be ignored.

## Install

Download this repository, extract the zip file, rename the folder to _instantdictionary.koplugin_ and move it into the KOReader _plugins_ folder.
Make sure the plugin is enabled under _Main Menu_ > _Options_ > _More Tools_ > _Plugin Management_.

The plugin offers no configuration methods in KOReader.

## Related work

This repository is inspired by https://github.com/ckilb/dictionarymode.koplugin, which works on a different principle.
Instead of triggering a long press action, the above mentioned repository implements an instant dictionary behaviour by directly calling languagesupport and triggering a LookupWord event.