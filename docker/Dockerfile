# resume-latex - the toolchain resume-generator needs, and nothing else.
#
# Build:  docker build -t resume-latex:1 docker/
# Use:    via bin/latex-shim, symlinked onto PATH under each tool name.
#
# Contains no application code and no personal data. The knowledge base is
# bind-mounted at run time and is never baked into the image.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      texlive-latex-recommended \
      texlive-latex-extra \
      texlive-fonts-recommended \
      texlive-fonts-extra \
      texlive-xetex \
      texlive-luatex \
      latexmk \
      poppler-utils \
      python3 \
      python3-yaml \
      fontconfig \
 && rm -rf /var/lib/apt/lists/*

# The container runs as the caller's uid, which has no home directory, so TeX
# needs a writable place for its font and format caches.
ENV TEXMFVAR=/tmp/texmf-var \
    TEXMFCONFIG=/tmp/texmf-config \
    HOME=/tmp

WORKDIR /work

# Ubuntu does not pull TeX Gyre in through the packages above when recommends
# are disabled. Template 6 requires tgpagella.sty. Keep this small package in
# its own final layer so rebuilding a released image can reuse the costly TeX
# toolchain layer.
RUN apt-get update && apt-get install -y --no-install-recommends \
      tex-gyre \
 && rm -rf /var/lib/apt/lists/*
