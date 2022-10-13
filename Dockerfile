# --------------> For some extra tooling
FROM busybox:1.35.0-uclibc as busybox

# --------------> The build image
FROM node:18.10-bullseye AS build
ARG NPM_TOKEN
RUN apt-get update && apt-get install -y --no-install-recommends bash-static
WORKDIR /pipeline/source
COPY package.json .yarnrc.yml yarn.lock /pipeline/source/
COPY .yarn /pipeline/source/.yarn

RUN yarn config set npmScopes.gasbuddy.npmRegistryServer "https://registry.npmjs.org" \
    && yarn config set npmScopes.gasbuddy.npmAlwaysAuth true \
    && yarn config set npmScopes.gasbuddy.npmAuthToken $NPM_TOKEN \
    && yarn plugin import workspace-tools \
    && yarn workspaces focus --production && \
    rm -rf .yarnrc.yml .yarn && \
    # Temporary until bcrypt fixes stuff
    chmod a+rx /pipeline/source/node_modules/bcrypt/lib/binding/napi-v3/bcrypt_lib.node

## --------------> Add to default image
FROM gcr.io/distroless/nodejs-debian11:18 as base
COPY --from=busybox /bin/busybox /bin/busybox
RUN ["/bin/busybox", "ln", "/bin/busybox", "/bin/sh"]
RUN /bin/busybox ln /bin/sh /bin/chmod && \
  /bin/busybox ln /bin/busybox /bin/cp && \
  /bin/busybox ln /bin/busybox /bin/find && \
  /bin/busybox ln /bin/busybox /bin/grep && \
  /bin/busybox ln /bin/busybox /bin/ls && \
  /bin/busybox ln /bin/busybox /bin/more && \
  /bin/busybox ln /bin/busybox /bin/ping && \
  /bin/busybox ln /bin/busybox /bin/sleep && \
  /bin/busybox ln /bin/busybox /bin/telnet && \
  /bin/busybox ln /bin/busybox /bin/vi

## --------------> The production image
FROM base
ENV NODE_ENV production
USER nonroot
WORKDIR /pipeline/source
COPY --from=busybox /bin/busybox /bin/busybox
COPY --chown=nonroot:nonroot --from=build /pipeline/source/node_modules /pipeline/source/node_modules
COPY --chown=nonroot:nonroot package.json /pipeline/source/
COPY --chown=nonroot:nonroot build/ /pipeline/source/build/
COPY --chown=nonroot:nonroot src/ /pipeline/source/src/
COPY --chown=nonroot:nonroot config/ /pipeline/source/config/
COPY --chown=nonroot:nonroot migrations/ /pipeline/source/migrations/
COPY --chown=nonroot:nonroot api/ /pipeline/source/api/
COPY --chown=nonroot:nonroot static/ /pipeline/source/static/
CMD ["node_modules/@gasbuddy/service/build/bin/start-service.js"]
