# Running resume-generator without installing TeX

On a Linux host with Docker but no TeX, build the bundled image once and put
the shims on `PATH`. The skill then works unchanged: `env-probe.sh`,
`preflight.sh`, `build.sh`, `lint-tex.sh`, and `qa-gate.sh` resolve the TeX and
Poppler tools by name.

## Build

    docker build -t resume-latex:1 docker/

The image is roughly 2.5 GB. Docker must be usable by your account. If the host
already permits non-interactive Docker through sudo, set
`RESUME_LATEX_SUDO=1`; the shim will invoke `sudo -n docker`. Otherwise,
configure Docker access according to the host's security policy.

## Install the shims

    mkdir -p ~/.local/bin
    for t in pdflatex xelatex lualatex latexmk pdftotext pdfinfo pdftoppm; do
      ln -sf "$PWD/bin/latex-shim" ~/.local/bin/"$t"
    done

Make sure `~/.local/bin` comes before any system TeX on your `PATH`.

## Verify

    bash skills/resume-generator/tests/env-probe.sh

Expect `STATUS=ok`, a non-empty path for every tool, and `PYYAML=yes`.

## Path behavior

The shim mounts the current directory at the same absolute path inside the
container. Relative paths and absolute paths beneath that directory therefore
work, including the absolute PDF and PNG paths used by `build.sh`. For
`pdftotext`, an explicit absolute output outside the current directory gets a
second narrow bind mount for its containing directory; this supports the
temporary text extraction used by `build.sh`. The shim mounts only the
directory explicitly named by that output path; it adds no blanket temporary
or home-directory mount.

Run the generator from the knowledge-repository root (or another ancestor of
the output directory). An absolute input or output path outside the current
directory is outside the mount and cannot be accessed by the container.

## Notes

- Files are written as your own uid, not root, because the shim passes
  `--user "$(id -u):$(id -g)"`.
- Point the shims at a different image with `RESUME_LATEX_IMAGE`.
- Use an existing non-interactive sudo policy with `RESUME_LATEX_SUDO=1`.
