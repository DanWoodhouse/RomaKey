# Web preview

`keyboard-preview.html` is a single-page copy of the keyboards' logic, for trying the layout,
mode wheel, suggestions, emoji panel and settings in a browser. It has a test checklist
covering every feature. Opened in Claude (claude.ai or the Claude app), its ✨ AI panel sends
the app's exact prompts to Claude, with the viewer's permission, and runs the same checks on the
answers; on iPhone the same prompts run on Apple's on-device model. Open it directly, or rebuild it after changing `preview.src.html`:

```sh
python3 build.py
```

- `table.json`: the romaji table, matching `RomajiTable.swift`.
- English word pairs for predictive text come from KeyboardCore's `bigrams.tsv`, the same table the app uses.
- `words.txt`: the 25,000 most common English words, most frequent first, from
  [wordfreq](https://github.com/rspeer/wordfreq) by Robyn Speer (data under CC BY-SA 4.0).
  The app uses Apple's spell checker instead; this list stands in for it in the browser.
