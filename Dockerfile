# --------------> For some extra tooling
FROM public.ecr.aws/docker/library/busybox:1.35.0-uclibc as busybox

# --------------> The build image
FROM public.ecr.aws/docker/library/node:18.19-bullseye AS build
ARG REPO_ORG
ARG BUILD_NODE_ENV=production
WORKDIR /pipeline/source
COPY package.json .yarnrc.yml yarn.lock coconfig.* /pipeline/source/
COPY .yarn /pipeline/source/.yarn
COPY --from=busybox /bin/busybox /staging/busybox

# Setup busybox for distroless. It's a bit against the spirit of distroless, but it's how we choose to roll
RUN ln -sr /staging/busybox /staging/sh && \
    ln -sr /staging/busybox /staging/chown && \
    ln -sr /staging/busybox /staging/cp && \
    ln -sr /staging/busybox /staging/env && \
    ln -sr /staging/busybox /staging/find && \
    ln -sr /staging/busybox /staging/grep && \
    ln -sr /staging/busybox /staging/kill && \
    ln -sr /staging/busybox /staging/ls && \
    ln -sr /staging/busybox /staging/more && \
    ln -sr /staging/busybox /staging/ping && \
    ln -sr /staging/busybox /staging/ps && \
    ln -sr /staging/busybox /staging/sleep && \
    ln -sr /staging/busybox /staging/tar && \
    ln -sr /staging/busybox /staging/telnet && \
    ln -sr /staging/busybox /staging/vi && \
    ln -sr /staging/busybox /staging/wget

# Run our custom yarn setup
ENV NODE_ENV=$BUILD_NODE_ENV
RUN --mount=type=secret,id=NPM_TOKEN \
    yarn config set npmScopes.$REPO_ORG.npmRegistryServer "https://registry.npmjs.org" \
    && yarn config set npmScopes.$REPO_ORG.npmAlwaysAuth true \
    && yarn config set npmScopes.$REPO_ORG.npmAuthToken $(cat /run/secrets/NPM_TOKEN) \
    && yarn plugin import workspace-tools \
    && yarn workspaces focus --production \
    && rm -rf .yarnrc.yml .yarn \
    && echo '#!/bin/sh\n/nodejs/bin/node node_modules/@gasbuddy/service/build/bin/start-service.js --built "$@"' > /staging/start \
    && echo '#!/bin/sh\n/nodejs/bin/node node_modules/@gasbuddy/service/build/bin/start-service.js --repl "$@"' > /staging/repl \
    && chmod a+rx /staging/start /staging/repl \
    && true

## --------------> Add to default image
# Switched from gcr.io/distroless/nodejs-debian11:18 to AWS public ECR mirror to comply
# with our move off Docker Hub / gcr.io on self-hosted runners. The slim variant ships with
# /usr/local/bin/node; we symlink it to /nodejs/bin/node and create a `nonroot` user
# (uid/gid 65532) so existing helm securityContext and start-script contracts continue to work.
# Pinned to 18.20-bullseye-slim — Node 18.20.x has globalThis.crypto (required by
# @smithy/core v3+ used by @gasbuddy/client-sqs); the previously floating distroless `:18`
# tag drifted to 18.15.0 and broke startup.
FROM public.ecr.aws/docker/library/node:18.20-bullseye-slim as base
RUN groupadd --system --gid 65532 nonroot \
    && useradd --system --uid 65532 --gid 65532 --home /home/nonroot --create-home --shell /sbin/nologin nonroot \
    && mkdir -p /nodejs/bin \
    && ln -s /usr/local/bin/node /nodejs/bin/node \
    && mkdir -p /pipeline/source \
    && chown nonroot:nonroot /pipeline/source
COPY --from=build --chown=nonroot:nonroot /staging/ /bin/
ENTRYPOINT ["/nodejs/bin/node"]

## --------------> Build the pipeline directory
FROM base as final
USER nonroot
WORKDIR /pipeline/source
COPY --chown=nonroot:nonroot --from=build /pipeline/source/node_modules /pipeline/source/node_modules
COPY --chown=nonroot:nonroot package.json next.config.* coconfig.* /pipeline/source/
COPY --chown=nonroot:nonroot build/ /pipeline/source/build/
COPY --chown=nonroot:nonroot build-static/ /pipeline/source/build-static/
COPY --chown=nonroot:nonroot static/ /pipeline/source/static/
COPY --chown=nonroot:nonroot src/ /pipeline/source/src/
COPY --chown=nonroot:nonroot config/ /pipeline/source/config/
COPY --chown=nonroot:nonroot migrations/ /pipeline/source/migrations/
COPY --chown=nonroot:nonroot api/ /pipeline/source/api/
COPY --chown=nonroot:nonroot public/ /pipeline/source/public/
COPY --chown=nonroot:nonroot private/ /pipeline/source/private/

## --------------> Flatten where possible
FROM base
ARG BUILD_NODE_ENV=production
USER nonroot
ENV NODE_ENV=$BUILD_NODE_ENV
ENV NODE_NO_WARNINGS 1
ENV NO_PRETTY_LOGS 1
ENV PATH /nodejs/bin:$PATH
WORKDIR /pipeline/source
CMD ["node_modules/@gasbuddy/service/build/bin/start-service.js"]
COPY --from=final --chown=nonroot:nonroot /pipeline/source /pipeline/source
