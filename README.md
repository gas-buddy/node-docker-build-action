node-docker-build-action
===

Build a GasBuddy service into a docker container and deploy it to an container registry.

Uses node:18.10-bullseye for installing packages and building and then gcr.io/distroless/nodejs-debian11:18
at runtime. At time of writing, minimal service container size was about 230MB. Previous alpine based
images were 80MB, so this isn't great, but I think having a standard, modern, and secure container
like gcr distroless is probably worth the tradeoff.
