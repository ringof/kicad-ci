# syntax=docker/dockerfile:1

# Reusable KiCad 10 + KiBot CI base with a vector PDF overlay capability
# (PyMuPDF / fitz), used to composite KiCad's native drill-map PDF onto a
# framed drawing-sheet template while staying 100% vector (not raster).
#
# Base: INTI-CMNB kicad10_auto (KiCad 10 + KiBot + ghostscript + ImageMagick
# + poppler). Pinned by digest for byte-for-byte reproducible CI — never
# ship FROM ...:latest. Resolve/refresh the digest with:
#   docker buildx imagetools inspect ghcr.io/inti-cmnb/kicad10_auto:latest
ARG BASE=ghcr.io/inti-cmnb/kicad10_auto@sha256:46b44e62b483aba94085ba53f3efd15f9b2625c191ac2f6931ba34058bec1bfb
FROM ${BASE}

# PyMuPDF (fitz): vector PDF overlay. Page.show_pdf_page() embeds the source
# page as a Form XObject, so the composited drill map remains fully zoomable.
#
# CRITICAL: this image ships TWO Python interpreters:
#   - /usr/local/bin/python3  -> KiBot's interpreter, and the `python3` on PATH
#   - /usr/bin/python3        -> the Debian system interpreter
# The consuming project's gen_docs.sh probes `python3` (PATH) first and uses the
# first interpreter that can `import fitz`. So fitz MUST be importable by the
# PATH `python3` (= /usr/local/bin/python3). Installing only into the Debian
# system python (apt install python3-pymupdf) would NOT satisfy that probe.
#
# Therefore install into the PATH python. PyMuPDF ships manylinux wheels, so
# this is a fast wheel install (no compile). Version-pinned for reproducibility.
ARG PYMUPDF_VERSION=1.24.14
RUN set -eux; \
    python3 -m ensurepip --upgrade 2>/dev/null || \
      { curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py; \
        python3 /tmp/get-pip.py; rm -f /tmp/get-pip.py; }; \
    python3 -m pip install --no-cache-dir --break-system-packages \
        "PyMuPDF==${PYMUPDF_VERSION}"

# Fail the BUILD if the PATH python can't import fitz — never ship a broken image.
RUN set -eux; \
    echo "PATH python: $(readlink -f "$(command -v python3)")"; \
    python3 -c "import fitz; print('PyMuPDF OK:', fitz.__version__)"
