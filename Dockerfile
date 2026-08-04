# LPS2 — the engine, the HTTP API and the web IDE in one image.
#
#   docker build -t lps2 .
#   docker run -p 3060:3060 lps2            # http://localhost:3060/
#   docker run -p 3060:3060 -e LPS_TOKEN=secret lps2
#
# Deployed to fly.io by ./buildPush.sh; see docs/deploy.md, which also covers
# running it alongside LogicalEnglish2 so that `.le` programs work.

# ---- stage 1: the IDE ------------------------------------------------------
# Monaco, Konva and three.js are not things you paste into a page, so since M14
# the UI has a real build. It stays in its own stage: the engine depends on
# SWI-Prolog and nothing else, and the image that ships has no Node in it.
FROM node:22-slim AS ui
WORKDIR /ui
COPY ui/package.json ui/package-lock.json* ./
RUN npm install --no-audit --no-fund
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

RUN chmod +x lps myswipl.sh

ARG BUILD_INFO="unknown"
RUN echo "${BUILD_INFO}" > build_info.txt

# Fail the BUILD, not the running server, if the engine does not load.
RUN swipl -q -g "consult('src/lps.pl')" -g "halt(0)" -t "halt(1)"

EXPOSE 3060

# LPS_TOKEN, when set, is required in every request body as "token".
# LPS_LE2_URL, when set, is an LE2 /leapi endpoint; without it a `.le` program
# is refused with a message rather than guessed at (docs/le_lps_interface.md).
ENV LPS_PORT=3060

CMD ["sh", "-c", "exec swipl -q -g \"consult('src/lps.pl')\" -g \"lps_cli:main(['ide','--port','${LPS_PORT}'])\" -t halt"]
