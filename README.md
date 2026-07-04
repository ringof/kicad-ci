# kicad-ci

A small, reusable **KiCad 10 + KiBot** CI base image published to GHCR as
[`ghcr.io/ringof/kicad-ci`](https://github.com/ringof/kicad-ci/pkgs/container/kicad-ci).

It extends the [INTI-CMNB](https://github.com/INTI-CMNB/kicad_auto)
`kicad10_auto` image (KiCad 10 + KiBot + ghostscript + ImageMagick + poppler)
with exactly **one** addition: a **vector PDF overlay capability**
([PyMuPDF](https://pymupdf.readthedocs.io/) / `fitz`).

## Why it exists

Consuming hardware projects generate a fabrication-drawing PDF with a KiCad
drawing sheet (title block / frame) on every page — **except the drill map**.
KiCad's drill-map generator (`GENDRILL_WRITER_BASE::genDrillMapFile`) builds its
own internal `PDF_PLOTTER` and never plots a drawing sheet; there is no hook in
`kicad-cli` or the `pcbnew` Python API to add one. (Upstream work-item 12690
tracks the gap and is unassigned.)

The only way to frame the drill map is to **overlay** KiCad's native (vector)
drill-map PDF onto a native (vector) frame-template PDF. Done with a
vector-aware tool this stays **100% vector, not raster**: PyMuPDF's
`Page.show_pdf_page()` embeds the source page as a Form XObject, so the result
is fully zoomable. That is the single capability this image adds on top of the
stock INTI-CMNB base.

Baking PyMuPDF into a custom image (rather than `pip install`-ing at runtime) is
necessary because the base image has no usable pip out of the box and PEP 668
blocks a naive runtime install. Baking it in also lets us **pin the base off
`:latest`** — the larger sustainability win: byte-for-byte reproducible fab
packages.

### The two-interpreter detail (important)

The base image ships **two** Python interpreters:

| Path | Role |
| --- | --- |
| `/usr/local/bin/python3` | KiBot's interpreter — **this is `python3` on `PATH`** |
| `/usr/bin/python3` | the Debian system interpreter |

Consuming projects' `gen_docs.sh` probes `python3` (PATH) first and uses the
first interpreter that can `import fitz`. So PyMuPDF is installed into the
**PATH python** (`/usr/local/bin/python3`), not the Debian system python. The
Dockerfile's final `import fitz` line is a hard build-time gate — the image
cannot be published if that interpreter can't import fitz.

## Consuming this image

Point your project's CI `container.image` at a **pinned, immutable tag**:

```yaml
# before
container:
  image: ghcr.io/inti-cmnb/kicad10_auto:latest

# after — pin to an immutable dated tag (never :10 in consumers)
container:
  image: ghcr.io/ringof/kicad-ci:10-20260704
```

No other change is needed: `fitz` is importable by the PATH `python3`, so a
`gen_docs.sh` that probes for a fitz-capable python enables framed drill maps
automatically.

Because the package is **public**, it pulls with **no auth** from any repo.

## Tags

| Tag | Mutability | Use |
| --- | --- | --- |
| `:10` | moving — republished on every build | convenience only |
| `:10-YYYYMMDD` | immutable | **pin your CI to this** |
| `:sha-<commit>` | immutable | pin to an exact source commit |

**Consuming projects should pin to `:10-YYYYMMDD` or a `@sha256:` digest**, never
`:10`, so their CI never shifts unexpectedly.

## Bumping the base (e.g. new KiCad release)

One place to change; each project adopts on its own schedule.

1. Resolve the new base digest:
   ```sh
   docker buildx imagetools inspect ghcr.io/inti-cmnb/kicad10_auto:latest \
     | grep -i digest
   ```
2. Update the `BASE` `@sha256:` digest in [`Dockerfile`](./Dockerfile).
   (Optionally bump `PYMUPDF_VERSION` too.)
3. Merge to `main`. The [`build-ci-image`](./.github/workflows/build-ci-image.yml)
   workflow rebuilds, runs the smoke tests, and republishes the tags above.
4. In each consuming project, bump the pinned `:10-YYYYMMDD` tag when ready.

## How it's built & verified

The workflow builds the image, **loads it locally, and runs the acceptance
gates before publishing** — nothing ships unless all pass:

1. `import fitz` succeeds on the **PATH** `python3` (also enforced in the Dockerfile).
2. A real vector overlay round-trips: `show_pdf_page()` nests a source page and
   saves a valid PDF.
3. Base tools remain intact: `kicad-cli version` and `kibot --version` both run.

The base is pinned by `@sha256:` digest — there is no `:latest` in `FROM`.

The workflow triggers only on changes to the `Dockerfile` or the workflow itself
(and on manual `workflow_dispatch`) — consuming projects just pull the finished
image.

## Package visibility

The GHCR package `kicad-ci` must be **Public** (package settings → Danger Zone →
Change visibility → Public). This is a one-time manual step after the first
successful build. Public makes it pullable with no auth and keeps GHCR
storage/bandwidth free. The image contains only public tools — no secrets,
source, or keys.
