# website: loco's product page

One static page, published to https://shreeve.github.io/loc/ by
`.github/workflows/pages.yml` whenever `website/` changes on `main`.
There is no build step: the browser compiles the page's Rip and its
Tailwind classes as it loads.

| File | Holds |
|---|---|
| `index.html` | The shell: fonts, the Tailwind theme, the theme set before paint, and a plain fallback for no JavaScript. |
| `app.rip` | The page, as Rip components, with its data: languages, speed rows, flags, FAQ. |
| `demo.json` | loco's real output on the Rip repository, styled, for the terminal demo. |
| `demo.py` | Regenerates `demo.json` from `bin/loco`. |
| `rip.min.js`, `tailwind.min.js` | Rip's browser runtime and its vendored Tailwind 4 runtime, copied from Rip's `dist/@rip/` (Rip 20d29328). |
| `favicon.svg` | The icon. |

Preview it under a subpath, as Pages serves it:

```
python3 -m http.server -d . 8000    # from the repository root
open http://localhost:8000/website/
```

The speed rows in `app.rip` quote `rig/DESIGN.md`'s table; change both
together. After `rig/build.sh`, `python3 website/demo.py ~/Data/Code rip`
remakes the demo from a checkout of Rip at `~/Data/Code/rip`. To update the
runtimes, run `bun run browser` and `bun run tailwind` in Rip and copy the
two files from its `dist/@rip/`.
