# --------------> For some extra tooling
FROM busybox:1.35.0-uclibc as busybox

# --------------> The build image
FROM node:18.11-bullseye AS build
ARG NPM_TOKEN
ARG REPO_ORG
WORKDIR /pipeline/source
COPY package.json .yarnrc.yml yarn.lock /pipeline/source/
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
    ln -sr /staging/busybox /staging/telnet && \
    ln -sr /staging/busybox /staging/vi && \
    ln -sr /staging/busybox /staging/wget

# Run out custom yarn setup
RUN yarn config set npmScopes.$REPO_ORG.npmRegistryServer "https://registry.npmjs.org" \
    && yarn config set npmScopes.$REPO_ORG.npmAlwaysAuth true \
    && yarn config set npmScopes.$REPO_ORG.npmAuthToken $NPM_TOKEN \
    && yarn plugin import workspace-tools \
    && yarn workspaces focus --production && \
    rm -rf .yarnrc.yml .yarn && \
    echo '#!/bin/sh\n/nodejs/bin/node node_modules/@gasbuddy/service/build/bin/start-service.js --built "$@"' > /staging/start && \
    echo '#!/bin/sh\n/nodejs/bin/node node_modules/@gasbuddy/service/build/bin/start-service.js --repl "$@"' > /staging/repl && \
    chmod a+rx /staging/start /staging/repl

## --------------> Add to default image
FROM gcr.io/distroless/nodejs-debian11:18 as base
COPY --from=build --chown=nonroot:nonroot /staging/ /bin/

## --------------> Build the pipeline directory
FROM base as final
USER nonroot
WORKDIR /pipeline/source
COPY --chown=nonroot:nonroot --from=build /pipeline/source/node_modules /pipeline/source/node_modules
COPY --chown=nonroot:nonroot package.json /pipeline/source/
COPY --chown=nonroot:nonroot build/ /pipeline/source/build/
COPY --chown=nonroot:nonroot src/ /pipeline/source/src/
COPY --chown=nonroot:nonroot config/ /pipeline/source/config/
COPY --chown=nonroot:nonroot migrations/ /pipeline/source/migrations/
COPY --chown=nonroot:nonroot api/ /pipeline/source/api/
COPY --chown=nonroot:nonroot public/ /pipeline/source/public/
COPY --chown=nonroot:nonroot private/ /pipeline/source/private/

## --------------> Flatten where possible
FROM base
USER nonroot
ENV NODE_ENV production
ENV NODE_NO_WARNINGS 1
ENV NO_PRETTY_LOGS 1
WORKDIR /pipeline/source
CMD ["node_modules/@gasbuddy/service/build/bin/start-service.js"]
COPY --from=final --chown=nonroot:nonroot /pipeline/source /pipeline/source
