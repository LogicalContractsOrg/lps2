# LPS2 — the engine, the HTTP API and the web IDE in one image.
#
#   docker build -t lps2 .
#   docker run -p 3060:3060 lps2            # http://localhost:3060/
#   docker run -p 3060:3060 -e LPS_TOKEN=secret lps2
#
# Deployed to fly.io by ./buildPush.sh; see docs/dev/deploy.md.
#
# Logical English is compiled *in this process* (docs/dev/le-lps-interface.md §3.5),
# from a minimal copy of LE2's language service in vendor/le2/. Put one there
# before building:
#
#   tools/vendor_le2.sh /path/to/LogicalEnglish2 && docker build -t lps2 .
#
# Without it the image is exactly what it was before: everything works except
# `.le` files, which say which variable to set.

# ---- stage 1: the IDE ------------------------------------------------------
# Monaco, Konva and three.js are not things you paste into a page, so since M14
# the UI has a real build. It stays in its own stage: the engine depends on
# SWI-Prolog and nothing else, and the image that ships has no Node in it.
FROM node:22-slim AS ui
WORKDIR /ui
COPY ui/package.json ui/package-lock.json* ./
RUN npm install --no-audit --no-fund
#  The sources only: `.dockerignore` keeps every `node_modules` out of the
#  context, so this cannot land a host-platform esbuild on top of the one the
#  line above installed for this image.
COPY ui/ ./
COPY src/core/lps_ops.pl /src/core/lps_ops.pl
COPY tools/gen_monarch.pl /tools/gen_monarch.pl
COPY myswipl.sh /myswipl.sh
# The Monarch keyword lists are generated from the engine's operator table by a
# Prolog script; there is no Prolog here, so the build falls back to the
# checked-in copy in ui/src/generated/, which is exactly what that fallback is
# for.
RUN node build.mjs

# ---- stage 2: the engine ---------------------------------------------------
FROM swipl:latest

WORKDIR /app

COPY lps myswipl.sh ./
COPY src/ ./src/
COPY --from=ui /src/ide/dist/ ./src/ide/dist/
COPY examples/ ./examples/
COPY docs/ ./docs/
COPY conformance/ ./conformance/
COPY tools/ ./tools/

# The legacy tree is READ-ONLY (CLAUDE.md hard rule 1) but not optional: the
# IDE offers its CLOUT_workshop programs as examples, and ten corpus programs
# pull in engine/system/date_utils.pl through `:- include(system(...))`.
COPY legacy_lps1/ ./legacy_lps1/

# The vendored Logical English, if tools/vendor_le2.sh put one there. The
# directory itself is committed (vendor/README.md) so this COPY always has
# something to take; `lps_le_available/1` treats a vendor/le2 with no
# le_service.pl in it as "no LE2", which is the same state as not configuring
# one at all.
COPY vendor/ ./vendor/

RUN chmod +x lps myswipl.sh

ARG BUILD_INFO="unknown"
RUN echo "${BUILD_INFO}" > build_info.txt

# Fail the BUILD, not the running server, if the engine does not load — and, if
# a Logical English was vendored, if *it* does not load either. A broken vendor
# directory that only shows up when a user opens a `.le` is the failure this
# line is here to prevent.
RUN swipl -q -g "consult('src/lps.pl')" -g "halt(0)" -t "halt(1)"
#  `-g halt(0)` is not decoration: `-t halt(1)` is the *toplevel* goal, which
#  SWI runs after the `-g` goals whatever they did. Without an explicit
#  successful exit, a check that passed still exits 1 — which is exactly what
#  the first version of this line did, failing every build that had a working
#  Logical English in it.
RUN if [ -f vendor/le2/le_service.pl ]; then \
      swipl -q -g "load_files('vendor/le2/le_service.pl',[if(not_loaded),silent(true)])" \
               -g "le_service:le_service_version(V), format('vendored Logical English ~w~n',[V])" \
               -g "halt(0)" -t "halt(1)" ; \
    else echo "no vendor/le2: this image will not compile Logical English" ; fi

EXPOSE 3060

# LPS_TOKEN, when set, is required in every request body as "token".
#
# LPS_LE2_LIB points at the vendored language service, so `.le` programs compile
# in this process. An image built without the vendoring step has an empty
# directory there and Logical English is simply absent — never guessed at
# (docs/dev/le-lps-interface.md §3.6). LPS_LE2_URL still works, and takes over when
# there is nothing vendored.
ENV LPS_PORT=3060
ENV LPS_LE2_LIB=/app/vendor/le2

CMD ["sh", "-c", "exec swipl -q -g \"consult('src/lps.pl')\" -g \"lps_cli:main(['ide','--port','${LPS_PORT}'])\" -t halt"]
